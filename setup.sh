#!/usr/bin/env bash
""":"
# ==============================================================================
# 🐍 Bash/Python Polyglot Bootstrapper (Pymera + uv pattern)
# Uses uv to ensure managed Python (3.12) & virtualenv exist with LiteLLM,
# then seamlessly re-executes this file as a Python program.
# ==============================================================================
set -euo pipefail

APP_DIR="${HOME}/.claude-any-model"
VENV_DIR="${APP_DIR}/venv"
PYTHON_TARGET="3.12"

# 1. Locate or auto-install uv (ultra-fast standalone Python & package manager)
if command -v uv &>/dev/null; then
    UV_BIN="uv"
elif [ -x "${HOME}/.local/bin/uv" ]; then
    UV_BIN="${HOME}/.local/bin/uv"
elif [ -x "${HOME}/.cargo/bin/uv" ]; then
    UV_BIN="${HOME}/.cargo/bin/uv"
else
    echo -e "\033[1;34m[INFO]\033[0m Installing uv (fast standalone Python runtime manager)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || true
    if [ -x "${HOME}/.local/bin/uv" ]; then
        UV_BIN="${HOME}/.local/bin/uv"
    elif [ -x "${HOME}/.cargo/bin/uv" ]; then
        UV_BIN="${HOME}/.cargo/bin/uv"
    else
        UV_BIN=""
    fi
fi

# 2. Bootstrap virtual environment with target Python version
mkdir -p "${APP_DIR}"
if [ -n "${UV_BIN}" ]; then
    PYTHON_BIN="${VENV_DIR}/bin/python"
    if [ ! -x "${PYTHON_BIN}" ]; then
        echo -e "\033[1;34m[INFO]\033[0m Initializing Python ${PYTHON_TARGET} virtualenv with uv..."
        "${UV_BIN}" venv "${VENV_DIR}" --python "${PYTHON_TARGET}" --quiet
        "${UV_BIN}" pip install --python "${PYTHON_BIN}" 'fastapi<0.140' 'litellm[proxy]' --quiet
    fi
else
    # Fallback to system python3 if uv is unavailable
    PYTHON_BIN="${VENV_DIR}/bin/python3"
    if [ ! -x "${PYTHON_BIN}" ]; then
        if ! command -v python3 &>/dev/null; then
            echo -e "\033[1;31m[ERROR]\033[0m Python 3 is required but not found in PATH." >&2
            exit 1
        fi
        echo -e "\033[1;34m[INFO]\033[0m Initializing Python virtual environment..."
        python3 -m venv "${VENV_DIR}"
        "${VENV_DIR}/bin/pip" install --quiet --upgrade pip
        "${VENV_DIR}/bin/pip" install --quiet 'fastapi<0.140' 'litellm[proxy]'
    fi
fi

# 3. Determine script location (handle curl one-liner pipe vs local file)
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_PATH="${BASH_SOURCE[0]}"
else
    SCRIPT_PATH="${APP_DIR}/setup.sh"
    curl -fsSL https://raw.githubusercontent.com/axiomantic/claude-any-model/main/setup.sh -o "${SCRIPT_PATH}" 2>/dev/null || true
    chmod +x "${SCRIPT_PATH}"
fi

# 4. Re-execute this file using the virtualenv Python interpreter
if [ ! -t 0 ] && [ -e /dev/tty ]; then
    exec "${PYTHON_BIN}" "${SCRIPT_PATH}" "$@" < /dev/tty
else
    exec "${PYTHON_BIN}" "${SCRIPT_PATH}" "$@"
fi
exit 0

"""

# ==============================================================================
# Claude Any Model — Python Implementation
# ==============================================================================
import sys
import os
import re
import json
import uuid
import time
import shutil
import getpass
import platform
import subprocess
import urllib.request
from datetime import datetime

# Script & Daemon Metadata
VERSION = "1.3.0"
MODELS_LAST_REVISITED = "2026-08-21"
PORT = 3010
PLIST_LABEL = "com.claude-any-model"
APP_DIR = os.path.expanduser("~/.claude-any-model")
PLIST_PATH = os.path.expanduser(f"~/Library/LaunchAgents/{PLIST_LABEL}.plist")

# Formatters
def info(msg): print(f"\033[1;34m[INFO]\033[0m {msg}", file=sys.stderr)
def success(msg): print(f"\033[1;32m[SUCCESS]\033[0m {msg}", file=sys.stderr)
def warn(msg): print(f"\033[1;33m[WARN]\033[0m {msg}", file=sys.stderr)
def error(msg): print(f"\033[1;31m[ERROR]\033[0m {msg}", file=sys.stderr)
def header(msg):
    print(f"\n\033[1;36m============================================================\033[0m", file=sys.stderr)
    print(f"\033[1;36m  {msg} (v{VERSION})\033[0m", file=sys.stderr)
    print(f"\033[1;36m============================================================\033[0m", file=sys.stderr)

def safe_input(prompt_text, default_val=""):
    try:
        sys.stderr.write(prompt_text)
        sys.stderr.flush()
        line = sys.stdin.readline()
        if not line:
            return default_val
        val = line.strip()
        return val if val else default_val
    except KeyboardInterrupt:
        print("\n\033[1;33m[ABORTED]\033[0m Configuration cancelled by user.", file=sys.stderr)
        sys.exit(130)
    except (EOFError, Exception):
        return default_val

def detect_claude_3p_dir():
    system = platform.system()
    if system == "Darwin":
        return os.path.expanduser("~/Library/Application Support/Claude-3p/configLibrary")
    elif system == "Linux":
        return os.path.expanduser("~/.config/Claude-3p/configLibrary")
    elif system == "Windows":
        local_app_data = os.environ.get("LOCALAPPDATA", os.path.expanduser("~/AppData/Local"))
        return os.path.join(local_app_data, "Claude-3p", "configLibrary")
    else:
        return os.path.expanduser("~/Library/Application Support/Claude-3p/configLibrary")

CLAUDE_3P_DIR = detect_claude_3p_dir()

def ensure_dirs():
    os.makedirs(APP_DIR, exist_ok=True)
    os.makedirs(os.path.join(APP_DIR, "logs"), exist_ok=True)
    os.makedirs(CLAUDE_3P_DIR, exist_ok=True)
    if platform.system() == "Darwin":
        os.makedirs(os.path.expanduser("~/Library/LaunchAgents"), exist_ok=True)

def is_claude_running():
    try:
        res = subprocess.run(["pgrep", "-f", "Claude.app"], capture_output=True)
        return res.returncode == 0
    except Exception:
        return False

def check_claude_closed():
    if is_claude_running():
        warn("Claude Desktop is currently running.")
        print("Please quit Claude Desktop (\033[1;36mCmd+Q\033[0m) so updated model profiles load cleanly.", file=sys.stderr)
        safe_input("Press [Enter] once Claude Desktop is closed... ")
        while is_claude_running():
            warn("Claude Desktop is still running. Please quit Claude Desktop completely.")
            safe_input("Press [Enter] once Claude Desktop is closed... ")
        success("Claude Desktop is closed.")

def validate_openrouter_key(api_key):
    if not api_key or not api_key.startswith("sk-or-v1-"):
        return False, "Key must start with 'sk-or-v1-'"
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/auth/key",
        headers={
            "Authorization": f"Bearer {api_key}",
            "User-Agent": "Claude-Any-Model/1.3.0"
        }
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            if resp.status == 200:
                return True, "Key is valid and authenticated"
    except urllib.error.HTTPError as e:
        return False, f"HTTP Error {e.code}: {e.reason}"
    except Exception as e:
        return False, f"Connection error: {e}"
    return False, "Validation failed"

def find_existing_api_key():
    env_key = os.environ.get("OPENROUTER_API_KEY")
    if env_key and len(env_key.strip()) > 5:
        return env_key.strip()

    search_files = [
        os.path.join(APP_DIR, ".env"),
        os.path.expanduser("~/.claude-openrouter-models/.env"),
        os.path.expanduser("~/.claude-to-openrouter-proxy/.env"),
        os.path.expanduser("~/.litellm-proxy/.env"),
        os.path.expanduser("~/.zshrc"),
        os.path.expanduser("~/.bashrc"),
        os.path.expanduser("~/.config/fish/config.fish"),
    ]
    for sf in search_files:
        if os.path.exists(sf):
            try:
                with open(sf, "r", encoding="utf-8") as f:
                    for line in f:
                        if line.strip().startswith("OPENROUTER_API_KEY="):
                            val = line.strip().split("=", 1)[1].strip().strip('"').strip("'")
                            if val and len(val) > 5 and not val.startswith("your_"):
                                return val
                        elif "export OPENROUTER_API_KEY=" in line:
                            val = line.strip().split("export OPENROUTER_API_KEY=", 1)[1].strip().strip('"').strip("'")
                            if val and len(val) > 5 and not val.startswith("your_"):
                                return val
            except Exception:
                pass
    return None

def mask_key(key):
    if not key or len(key) <= 12:
        return "****"
    return f"{key[:8]}...{key[-4:]}"

def setup_env(force=False):
    env_path = os.path.join(APP_DIR, ".env")
    existing_key = find_existing_api_key()

    # If key is already available and not forcing, silently ensure .env exists and return
    if existing_key and not force:
        if not os.path.exists(env_path):
            with open(env_path, "w", encoding="utf-8") as f:
                f.write(f"OPENROUTER_API_KEY={existing_key}\nPORT={PORT}\n")
            os.chmod(env_path, 0o600)
        return

    api_key = None
    if existing_key:
        masked = mask_key(existing_key)
        info(f"Found existing OpenRouter API Key: \033[1;32m{masked}\033[0m")
        use_existing = safe_input("Use this API key? (Y/n): ", "y").lower()
        if use_existing in ("y", "yes", ""):
            api_key = existing_key

    if not api_key:
        print("\n\033[1;36m[SETUP]\033[0m An OpenRouter API key enables cloud models (Qwen, DeepSeek, Kimi, GPT-5 series, etc).", file=sys.stderr)
        print("         If you only want local models (Ollama / LM Studio / vLLM), press Enter to skip.\n", file=sys.stderr)
        prompt = "Enter OpenRouter API Key (sk-or-v1-...) or press Enter to skip: "
        if sys.stdin.isatty():
            try:
                entered = getpass.getpass(prompt).strip()
            except Exception:
                entered = safe_input(prompt, "")
        else:
            entered = safe_input(prompt, "")

        if entered:
            info("Validating key with OpenRouter API...")
            valid, msg = validate_openrouter_key(entered)
            if valid:
                success(f"OpenRouter API key verified successfully ({msg})")
                api_key = entered
            else:
                error(f"API key validation failed: {msg}")
                retry = safe_input("Use this key anyway? (y/N): ", "n").lower()
                if retry in ("y", "yes"):
                    api_key = entered
        else:
            info("Skipping OpenRouter API key — only local models will be available.")

    if os.path.exists(env_path):
        backup_env = f"{env_path}.bak.{int(datetime.now().timestamp())}"
        try:
            with open(env_path, "r", encoding="utf-8") as src, open(backup_env, "w", encoding="utf-8") as dst:
                dst.write(src.read())
        except Exception:
            pass

    with open(env_path, "w", encoding="utf-8") as f:
        f.write(f"OPENROUTER_API_KEY={api_key or ''}\nPORT={PORT}\n")
    os.chmod(env_path, 0o600)
    if api_key:
        success(f"OpenRouter API key saved to {env_path}")
    else:
        info(f"Environment file written to {env_path} (no OpenRouter key set)")


def read_current_config():
    config_path = os.path.join(APP_DIR, "config.yaml")
    current_map = {}
    if os.path.exists(config_path):
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                content = f.read()
            blocks = content.split("- model_name:")
            for b in blocks[1:]:
                lines = b.strip().split("\n")
                m_name = lines[0].strip()
                m_target_match = re.search(r"model:\s*([^\s]+)", b)
                if m_target_match:
                    raw_target = m_target_match.group(1).strip()
                    if raw_target.startswith("openrouter/"):
                        current_map[m_name] = raw_target[len("openrouter/"):]
                    elif raw_target.startswith("ollama/"):
                        current_map[m_name] = raw_target
                    elif raw_target.startswith("openai/"):
                        current_map[m_name] = raw_target
                    else:
                        current_map[m_name] = raw_target
        except Exception:
            pass
    return current_map

def fetch_local_engines():
    """Detect running local inference engines (Ollama, LM Studio, vLLM)."""
    engines = []

    # 1. Ollama (Default: http://localhost:11434)
    try:
        req = urllib.request.Request("http://localhost:11434/api/tags", headers={"User-Agent": "Claude-Models-Checker"})
        with urllib.request.urlopen(req, timeout=0.8) as resp:
            data = json.loads(resp.read().decode())
            models = data.get("models", [])
            if models:
                engines.append({
                    "provider": "ollama",
                    "name": "Ollama",
                    "api_base": "http://localhost:11434",
                    "models": [
                        {
                            "id": f"ollama/{m.get('name')}",
                            "raw_model_id": m.get("name"),
                            "name": f"{m.get('name')} (Ollama Local)",
                            "price_str": "$0.00 / Local",
                            "ctx_str": "Local Context",
                            "supports1m": False,
                            "provider": "ollama",
                            "api_base": "http://localhost:11434"
                        }
                        for m in models
                    ]
                })
    except Exception:
        pass

    # 2. LM Studio (Default: http://localhost:1234/v1)
    try:
        req = urllib.request.Request("http://localhost:1234/v1/models", headers={"User-Agent": "Claude-Models-Checker"})
        with urllib.request.urlopen(req, timeout=0.8) as resp:
            data = json.loads(resp.read().decode())
            models = data.get("data", [])
            if models:
                engines.append({
                    "provider": "lmstudio",
                    "name": "LM Studio",
                    "api_base": "http://localhost:1234/v1",
                    "models": [
                        {
                            "id": f"openai/{m.get('id')}",
                            "raw_model_id": m.get("id"),
                            "name": f"{m.get('id')} (LM Studio Local)",
                            "price_str": "$0.00 / Local",
                            "ctx_str": "Local Context",
                            "supports1m": False,
                            "provider": "openai",
                            "api_base": "http://localhost:1234/v1"
                        }
                        for m in models
                    ]
                })
    except Exception:
        pass

    # 3. vLLM / llama.cpp / custom local server (Default: http://localhost:8000/v1)
    try:
        req = urllib.request.Request("http://localhost:8000/v1/models", headers={"User-Agent": "Claude-Models-Checker"})
        with urllib.request.urlopen(req, timeout=0.8) as resp:
            data = json.loads(resp.read().decode())
            models = data.get("data", [])
            if models:
                engines.append({
                    "provider": "vllm",
                    "name": "vLLM / Local Server",
                    "api_base": "http://localhost:8000/v1",
                    "models": [
                        {
                            "id": f"openai/{m.get('id')}",
                            "raw_model_id": m.get("id"),
                            "name": f"{m.get('id')} (vLLM Local)",
                            "price_str": "$0.00 / Local",
                            "ctx_str": "Local Context",
                            "supports1m": False,
                            "provider": "openai",
                            "api_base": "http://localhost:8000/v1"
                        }
                        for m in models
                    ]
                })
    except Exception:
        pass

    return engines

def fetch_openrouter_catalog():
    info("Fetching live model catalog & pricing from OpenRouter API...")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/models",
        headers={"User-Agent": "Claude-Any-Model/1.3.0"}
    )
    catalog = {}
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode()).get("data", [])
            for m in data:
                mid = m.get("id", "")
                p_in = float(m.get("pricing", {}).get("prompt", 0)) * 1_000_000
                p_out = float(m.get("pricing", {}).get("completion", 0)) * 1_000_000
                ctx = int(m.get("context_length", 0))
                
                if ctx >= 1_000_000:
                    ctx_str = f"{ctx // 1_000_000}M Context"
                elif ctx > 0:
                    ctx_str = f"{ctx // 1_000}k Context"
                else:
                    ctx_str = "Unknown Context"

                catalog[mid] = {
                    "name": m.get("name", mid),
                    "price_str": f"${p_in:.2f}/${p_out:.2f}",
                    "ctx_str": ctx_str,
                    "supports1m": ctx >= 900_000
                }
        success(f"Loaded live pricing for {len(catalog)} models from OpenRouter API.")
    except Exception as e:
        warn(f"Could not reach OpenRouter API ({e}). Using built-in pricing estimates.")
    return catalog

def get_model_entry(catalog, model_id, fallback_name, fallback_price, fallback_ctx, fallback_1m, is_recommended=False):
    item = catalog.get(model_id)
    if item:
        return {
            "id": model_id,
            "raw_model_id": model_id,
            "name": fallback_name,
            "price_str": item["price_str"],
            "ctx_str": item["ctx_str"],
            "supports1m": item["supports1m"],
            "provider": "openrouter",
            "api_base": None,
            "is_recommended": is_recommended
        }
    return {
        "id": model_id,
        "raw_model_id": model_id,
        "name": fallback_name,
        "price_str": fallback_price,
        "ctx_str": fallback_ctx,
        "supports1m": fallback_1m,
        "provider": "openrouter",
        "api_base": None,
        "is_recommended": is_recommended
    }

def run_model_configuration():
    check_claude_closed()
    setup_env(force=False)
    catalog = fetch_openrouter_catalog()
    current_config = read_current_config()
    local_engines = fetch_local_engines()

    if local_engines:
        engine_summary = ", ".join([f"{e['name']} ({len(e['models'])} models)" for e in local_engines])
        info(f"Discovered local inference engine(s): \033[1;32m{engine_summary}\033[0m")

    tiers = [
        {
            "tier_name": "opus",
            "tier_label": "OPUS TIER (Heavyweight Reasoning & Complex Architecture)",
            "claude_name": "claude-opus-4",
            "options": [
                get_model_entry(catalog, "moonshotai/kimi-k3", "Kimi K3", "$3.00/$15.00", "1M Context", True, is_recommended=True),
                get_model_entry(catalog, "z-ai/glm-5.2", "GLM-5.2", "$0.97/$3.04", "1M Context", True),
                get_model_entry(catalog, "openai/gpt-5.6-terra", "GPT-5.6 Terra", "$2.00/$12.00", "1M Context", True),
                get_model_entry(catalog, "deepseek/deepseek-v4-pro-0813", "DeepSeek V4 Pro (0813 GA)", "$1.19/$3.56", "1M Context", True),
                get_model_entry(catalog, "anthropic/claude-sonnet-4.6", "Claude Sonnet 4.6", "$3.00/$15.00", "1M Context", True),
            ]
        },
        {
            "tier_name": "sonnet",
            "tier_label": "SONNET TIER (Fast Agentic Workhorse & Coding)",
            "claude_name": "claude-sonnet-4-5",
            "options": [
                get_model_entry(catalog, "qwen/qwen3-coder-next", "Qwen3 Coder Next", "$0.12/$0.80", "262k Context", False, is_recommended=True),
                get_model_entry(catalog, "anthropic/claude-sonnet-4", "Claude Sonnet 4", "$3.00/$15.00", "1M Context", True),
                get_model_entry(catalog, "deepseek/deepseek-chat", "DeepSeek V3", "$0.26/$1.03", "163k Context", False),
                get_model_entry(catalog, "qwen/qwen3-coder-flash", "Qwen3 Coder Flash", "$0.20/$0.97", "1M Context", True),
            ]
        },
        {
            "tier_name": "haiku",
            "tier_label": "HAIKU TIER (Maximum Speed & Low Cost)",
            "claude_name": "claude-3-haiku-20240307",
            "options": [
                get_model_entry(catalog, "deepseek/deepseek-v4-flash", "DeepSeek V4 Flash", "$0.08/$0.17", "1M Context", True, is_recommended=True),
                get_model_entry(catalog, "google/gemini-2.0-flash-001", "Gemini 2.0 Flash", "$0.10/$0.40", "1M Context", True),
                get_model_entry(catalog, "qwen/qwen3-coder-30b-a3b-instruct", "Qwen3 Coder 30B", "$0.07/$0.28", "262k Context", False),
                get_model_entry(catalog, "openai/gpt-5.6-luna", "GPT-5.6 Luna", "$0.20/$1.20", "1M Context", True),
            ]
        },
        {
            "tier_name": "fable",
            "tier_label": "FABLE TIER (Ultra-Heavyweight Multi-Step Agent)",
            "claude_name": "claude-fable-5",
            "options": [
                get_model_entry(catalog, "z-ai/glm-5.2", "GLM-5.2", "$0.97/$3.04", "1M Context", True, is_recommended=True),
                get_model_entry(catalog, "moonshotai/kimi-k3", "Kimi K3", "$3.00/$15.00", "1M Context", True),
                get_model_entry(catalog, "deepseek/deepseek-v4-pro-0813", "DeepSeek V4 Pro", "$1.19/$3.56", "1M Context", True),
                get_model_entry(catalog, "openai/gpt-5.6-terra", "GPT-5.6 Terra", "$2.00/$12.00", "1M Context", True),
            ]
        },
        {
            "tier_name": "mythos",
            "tier_label": "MYTHOS TIER (Frontier & Experimental Heavyweight)",
            "claude_name": "claude-mythos-1",
            "options": [
                get_model_entry(catalog, "anthropic/claude-opus-5", "Claude Opus 5", "$5.00/$25.00", "1M Context", True, is_recommended=True),
                get_model_entry(catalog, "moonshotai/kimi-k3", "Kimi K3 Ultra", "$3.00/$15.00", "1M Context", True),
                get_model_entry(catalog, "deepseek/deepseek-v4-pro-0813", "DeepSeek V4 Pro (Max)", "$1.19/$3.56", "1M Context", True),
                get_model_entry(catalog, "z-ai/glm-5.2", "GLM-5.2 (Reasoning)", "$0.97/$3.04", "1M Context", True),
            ]
        }
    ]

    header(f"Configure Inference Models for Claude Desktop (Curated: {MODELS_LAST_REVISITED})")
    print(f"\033[1;34m[INFO]\033[0m Curated model list last revisited: \033[1;36m{MODELS_LAST_REVISITED}\033[0m", file=sys.stderr)
    print("Select your target model for each Anthropic family tier.", file=sys.stderr)
    print("Supports OpenRouter cloud models as well as local engines (Ollama, LM Studio, vLLM).\n", file=sys.stderr)

    selections = []

    for idx, t in enumerate(tiers, 1):
        print(f"\033[1;35m--- [{idx}/5] {t['tier_label']} ---\033[0m", file=sys.stderr)

        current_model_id = current_config.get(t["claude_name"])
        matched_current_idx = None
        recommended_idx = 1

        all_options = list(t["options"])

        # Collect local models, group by engine
        local_by_engine = {}
        for engine in local_engines:
            for lm in engine["models"]:
                key = engine["name"]
                local_by_engine.setdefault(key, []).append(lm)
                all_options.append(lm)

        # Print OpenRouter cloud options
        openrouter_opts = [o for o in all_options if o.get("provider") == "openrouter"]
        if openrouter_opts:
            print(f"  \033[1;34m☁  OpenRouter\033[0m", file=sys.stderr)
        for opt_idx, opt in enumerate(all_options, 1):
            if opt.get("provider") != "openrouter":
                continue
            is_current = (current_model_id is not None and (opt["id"] == current_model_id or opt.get("raw_model_id") == current_model_id))
            if is_current:
                matched_current_idx = opt_idx
            if opt.get("is_recommended"):
                recommended_idx = opt_idx

            tags = []
            if opt.get("is_recommended"):
                tags.append("\033[1;32m(Recommended)\033[0m")
            if is_current:
                tags.append("\033[1;33m[CURRENT]\033[0m")
            tag_str = f"  {' '.join(tags)}" if tags else ""
            print(f"  {opt_idx}) {opt['name']:<26} {opt['price_str']:<14} [{opt['ctx_str']}]{tag_str}", file=sys.stderr)

        # Print local engine options, grouped by engine name
        printed_engines = set()
        for opt_idx, opt in enumerate(all_options, 1):
            prov = opt.get("provider")
            if prov not in ("ollama", "lmstudio", "vllm", "openai") or opt.get("api_base") is None:
                continue
            engine_name = opt.get("name", "").replace(f" ({opt.get('raw_model_id', '')})", "").strip()
            # Derive engine header from name
            if "Ollama" in opt.get("name", ""):
                header_key = "Ollama"
            elif "LM Studio" in opt.get("name", ""):
                header_key = "LM Studio"
            elif "vLLM" in opt.get("name", ""):
                header_key = "vLLM"
            else:
                header_key = prov.capitalize()
            if header_key not in printed_engines:
                print(f"  \033[1;36m⬡  {header_key} (Local)\033[0m", file=sys.stderr)
                printed_engines.add(header_key)

            is_current = (current_model_id is not None and (opt["id"] == current_model_id or opt.get("raw_model_id") == current_model_id))
            if is_current:
                matched_current_idx = opt_idx
            tags = []
            if is_current:
                tags.append("\033[1;33m[CURRENT]\033[0m")
            tag_str = f"  {' '.join(tags)}" if tags else ""
            raw_display = opt.get("raw_model_id", opt["id"])
            print(f"  {opt_idx}) {raw_display:<26} $0.00 / Local{tag_str}", file=sys.stderr)

        custom_openrouter_num = len(all_options) + 1
        custom_local_num = len(all_options) + 2
        custom_tag = ""
        if matched_current_idx is None and current_model_id:
            custom_tag = f" \033[1;33m[CURRENT: {current_model_id}]\033[0m"
            matched_current_idx = custom_openrouter_num

        print(f"  \033[1;33m✎  Custom\033[0m", file=sys.stderr)
        print(f"  {custom_openrouter_num}) Custom OpenRouter model ID{custom_tag}", file=sys.stderr)
        print(f"  {custom_local_num}) Custom local / OpenAI-compatible endpoint (Ollama, LM Studio, vLLM, custom URL)", file=sys.stderr)

        if matched_current_idx is not None:
            default_choice = str(matched_current_idx)
            if matched_current_idx == custom_openrouter_num:
                default_hint = f"default={default_choice} (Current: {current_model_id})"
            else:
                default_hint = f"default={default_choice} (Current)"
        else:
            default_choice = str(recommended_idx)
            default_hint = f"default={default_choice} (Recommended)"

        user_choice = safe_input(f"Select {t['tier_name'].upper()} model [1-{custom_local_num}, {default_hint}]: ", default_choice)

        try:
            choice_num = int(user_choice)
        except ValueError:
            choice_num = int(default_choice)

        if 1 <= choice_num <= len(all_options):
            chosen = all_options[choice_num - 1]
            provider = chosen.get("provider", "openrouter")
            model_id = chosen["raw_model_id"]
            api_base = chosen.get("api_base")
            label = f"{chosen['name']} ({chosen['price_str']})"
            supports1m = chosen["supports1m"]
        elif choice_num == custom_openrouter_num:
            default_custom = current_model_id if current_model_id else t["options"][0]["id"]
            custom_id = safe_input(f"Enter OpenRouter model ID [default={default_custom}]: ", default_custom)
            item = catalog.get(custom_id)
            if item:
                print(f"\033[1;32m[API Match]\033[0m Found {item['name']}: {item['price_str']} [{item['ctx_str']}]", file=sys.stderr)
                model_id = custom_id
                label = f"{item['name']} ({item['price_str']})"
                supports1m = item["supports1m"]
            else:
                custom_label = safe_input(f"Enter display label with price (e.g. {custom_id}): ", custom_id)
                custom_1m = safe_input("Does it support 1M context? (y/N): ", "n").lower() == "y"
                model_id = custom_id
                label = custom_label
                supports1m = custom_1m
            provider = "openrouter"
            api_base = None
        else:
            # Custom local / OpenAI-compatible endpoint
            print("\033[1;36m--- Custom Local / Remote Endpoint Configuration ---\033[0m", file=sys.stderr)
            endpoint_type = safe_input("Select engine type: [1] Ollama, [2] LM Studio / vLLM / OpenAI-compatible (default=1): ", "1")
            if endpoint_type == "2":
                provider = "openai"
                default_base = "http://localhost:1234/v1"
            else:
                provider = "ollama"
                default_base = "http://localhost:11434"

            api_base = safe_input(f"Enter API Base URL [default={default_base}]: ", default_base)
            model_id = safe_input(f"Enter Model Name (e.g. qwen2.5-coder:32b): ", "local-model")
            label = safe_input(f"Enter display label in Claude [default={model_id} (Local / $0.00)]: ", f"{model_id} (Local / $0.00)")
            supports1m = safe_input("Does it support 1M context? (y/N): ", "n").lower() == "y"

        selections.append({
            "tier": t["tier_name"],
            "claude_name": t["claude_name"],
            "provider": provider,
            "model_id": model_id,
            "api_base": api_base,
            "label": label,
            "supports1m": supports1m
        })
        print("", file=sys.stderr)

    # 1. Write Strict Guardrail & LiteLLM config.yaml
    os.makedirs(APP_DIR, exist_ok=True)
    allowed_models = [s["claude_name"] for s in selections]

    guardrail_py_path = os.path.join(APP_DIR, "guardrail.py")
    guardrail_code = f"""# Strict Model Guardrail - Blocks any request using unconfigured models
from litellm.integrations.custom_logger import CustomLogger
from fastapi import HTTPException

ALLOWED_MODELS = set({json.dumps(allowed_models)})

class StrictModelGuardrail(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type, **kwargs):
        requested_model = data.get("model")
        if requested_model and requested_model not in ALLOWED_MODELS:
            raise HTTPException(
                status_code=403,
                detail=f"[Strict Guardrail] Model '{{requested_model}}' is not permitted. Only configured models are allowed: {{sorted(list(ALLOWED_MODELS))}}"
            )
        return data

strict_guardrail = StrictModelGuardrail()
"""
    with open(guardrail_py_path, "w", encoding="utf-8") as f:
        f.write(guardrail_code)

    config_yaml_path = os.path.join(APP_DIR, "config.yaml")
    if os.path.exists(config_yaml_path):
        backup_yaml = f"{config_yaml_path}.bak.{int(datetime.now().timestamp())}"
        try:
            with open(config_yaml_path, "r", encoding="utf-8") as src, open(backup_yaml, "w", encoding="utf-8") as dst:
                dst.write(src.read())
        except Exception:
            pass

    yaml_lines = ["model_list:"]
    for s in selections:
        yaml_lines.append(f"  # Route {s['tier'].capitalize()} requests ({s['label']})")
        yaml_lines.append(f"  - model_name: {s['claude_name']}")
        yaml_lines.append(f"    litellm_params:")
        if s["provider"] == "openrouter":
            yaml_lines.append(f"      model: openrouter/{s['model_id']}")
            yaml_lines.append(f"      api_key: os.environ/OPENROUTER_API_KEY\n")
        elif s["provider"] == "ollama":
            raw_id = s['model_id'][len("ollama/"):] if s['model_id'].startswith("ollama/") else s['model_id']
            yaml_lines.append(f"      model: ollama/{raw_id}")
            yaml_lines.append(f"      api_base: {s['api_base'] or 'http://localhost:11434'}\n")
        elif s["provider"] in ("openai", "lmstudio", "vllm"):
            raw_id = s['model_id'][len("openai/"):] if s['model_id'].startswith("openai/") else s['model_id']
            yaml_lines.append(f"      model: openai/{raw_id}")
            yaml_lines.append(f"      api_base: {s['api_base'] or 'http://localhost:1234/v1'}")
            yaml_lines.append(f"      api_key: dummy-key\n")
        else:
            yaml_lines.append(f"      model: {s['model_id']}")
            if s.get("api_base"):
                yaml_lines.append(f"      api_base: {s['api_base']}")
            yaml_lines.append(f"      api_key: dummy-key\n")

    yaml_lines.append("litellm_settings:")
    yaml_lines.append("  drop_params: true")
    yaml_lines.append("  callbacks:")
    yaml_lines.append("    - guardrail.strict_guardrail\n")
    yaml_lines.append("general_settings:")
    yaml_lines.append("  master_key: dummy-key\n")

    with open(config_yaml_path, "w", encoding="utf-8") as f:
        f.write("\n".join(yaml_lines))
    success(f"Generated LiteLLM config at: {config_yaml_path} (Strict model blocking: ACTIVE)")

    # 2. Write Claude 3P configLibrary JSON
    os.makedirs(CLAUDE_3P_DIR, exist_ok=True)
    meta_path = os.path.join(CLAUDE_3P_DIR, "_meta.json")
    meta = {"appliedId": None, "entries": []}
    if os.path.exists(meta_path):
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                loaded = json.load(f)
                if isinstance(loaded, dict):
                    meta = loaded
        except Exception:
            pass

    entries = meta.get("entries", [])
    applied_id = meta.get("appliedId")

    # Find existing OpenRouter gateway entry or create a dedicated entry without overwriting others
    gateway_entry = next((e for e in entries if e.get("name") in ("OpenRouter Gateway", "Default") or (applied_id and e.get("id") == applied_id)), None)
    if gateway_entry:
        applied_id = gateway_entry.get("id")
        gateway_entry["name"] = "OpenRouter Gateway"
    else:
        applied_id = str(uuid.uuid4())
        entries.append({"id": applied_id, "name": "OpenRouter Gateway"})

    meta["appliedId"] = applied_id
    meta["entries"] = entries
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    profile_path = os.path.join(CLAUDE_3P_DIR, f"{applied_id}.json")
    if os.path.exists(profile_path):
        backup_profile = f"{profile_path}.bak.{int(datetime.now().timestamp())}"
        try:
            with open(profile_path, "r", encoding="utf-8") as src, open(backup_profile, "w", encoding="utf-8") as dst:
                dst.write(src.read())
        except Exception:
            pass

    inference_models = []
    for s in selections:
        inference_models.append({
            "name": s["claude_name"],
            "labelOverride": s["label"],
            "supports1m": s["supports1m"],
            "prefer1m": s["supports1m"],
            "anthropicFamilyTier": s["tier"],
            "isFamilyDefault": True
        })

    config_data = {
        "inferenceGatewayBaseUrl": f"http://127.0.0.1:{PORT}",
        "inferenceGatewayApiKey": "dummy-key",
        "modelDiscoveryEnabled": False,
        "inferenceModels": inference_models,
        "inferenceProvider": "gateway",
        "inferenceCredentialKind": "static",
        "claudeAiImport": {
            "enabled": True,
            "exportEnabled": True,
            "bannerBehavior": "detect"
        }
    }

    with open(profile_path, "w", encoding="utf-8") as f:
        json.dump(config_data, f, indent=2)
    
    # Save a persistent backup copy in ~/.claude-any-model
    backup_copy = os.path.join(APP_DIR, "gateway_profile.json")
    try:
        with open(backup_copy, "w", encoding="utf-8") as f:
            json.dump(config_data, f, indent=2)
        with open(os.path.join(APP_DIR, ".last_applied_id"), "w", encoding="utf-8") as f:
            f.write(applied_id.strip())
    except Exception:
        pass

    success(f"Synchronized Claude 3P config profile at: {profile_path}")

def create_runner_script():
    runner = os.path.join(APP_DIR, "run_proxy.sh")
    content = f"""#!/usr/bin/env bash
set -euo pipefail
APP_DIR="{APP_DIR}"
cd "$APP_DIR"

if [ -f "$APP_DIR/.env" ]; then
    set -a
    source "$APP_DIR/.env"
    set +a
fi

export PYTHONPATH="$APP_DIR"
exec "{APP_DIR}/venv/bin/litellm" --config "$APP_DIR/config.yaml" --port {PORT} --host 127.0.0.1
"""
    with open(runner, "w", encoding="utf-8") as f:
        f.write(content)
    os.chmod(runner, 0o755)
    success(f"Runner script created at: {runner}")

def install_service():
    if platform.system() != "Darwin":
        info("Non-macOS system: Launch proxy manually using ~/.claude-any-model/run_proxy.sh")
        return

    launch_agents = os.path.expanduser("~/Library/LaunchAgents")
    os.makedirs(launch_agents, exist_ok=True)
    runner = os.path.join(APP_DIR, "run_proxy.sh")

    plist_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{runner}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>{APP_DIR}/logs/litellm.out.log</string>
    <key>StandardErrorPath</key>
    <string>{APP_DIR}/logs/litellm.err.log</string>
    <key>WorkingDirectory</key>
    <string>{APP_DIR}</string>
</dict>
</plist>
"""
    with open(PLIST_PATH, "w", encoding="utf-8") as f:
        f.write(plist_content)

    subprocess.run(["launchctl", "unload", PLIST_PATH], capture_output=True)
    subprocess.run(["launchctl", "load", PLIST_PATH], capture_output=True)
    success(f"LaunchAgent registered and loaded: {PLIST_PATH}")

def uninstall_service():
    check_claude_closed()
    header("Uninstalling Claude Any Model")
    if platform.system() == "Darwin" and os.path.exists(PLIST_PATH):
        subprocess.run(["launchctl", "unload", PLIST_PATH], capture_output=True)
        try:
            os.remove(PLIST_PATH)
        except Exception:
            pass
        success(f"Unloaded and removed {PLIST_PATH}")

    meta_path = os.path.join(CLAUDE_3P_DIR, "_meta.json")
    if os.path.exists(meta_path):
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                meta = json.load(f)
            meta["appliedId"] = None
            with open(meta_path, "w", encoding="utf-8") as f:
                json.dump(meta, f, indent=2)
            success("Cleared appliedId in Claude 3P config.")
        except Exception:
            pass

    purge = safe_input("Delete proxy directory and cached virtualenv ~/.claude-any-model? (y/N): ", "n").lower()
    if purge in ("y", "yes"):
        if os.path.exists(APP_DIR):
            shutil.rmtree(APP_DIR)
        success(f"Removed {APP_DIR}.")
    success("Uninstall complete.")

def get_active_claude_mode():
    meta_path = os.path.join(CLAUDE_3P_DIR, "_meta.json")
    if not os.path.exists(meta_path):
        return "regular"
    try:
        with open(meta_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
            applied_id = meta.get("appliedId")
            if applied_id:
                profile_path = os.path.join(CLAUDE_3P_DIR, f"{applied_id}.json")
                if os.path.exists(profile_path):
                    with open(profile_path, "r", encoding="utf-8") as pf:
                        pdata = json.load(pf)
                        if pdata.get("inferenceProvider") == "gateway":
                            return "gateway"
    except Exception:
        pass
    return "regular"

def switch_claude_mode(target_mode="toggle"):
    current = get_active_claude_mode()
    meta_path = os.path.join(CLAUDE_3P_DIR, "_meta.json")
    state_file = os.path.join(APP_DIR, ".last_applied_id")

    if not target_mode or target_mode == "toggle":
        target_mode = "regular" if current == "gateway" else "gateway"

    target_mode = target_mode.lower()
    if target_mode in ("regular", "native", "1p", "official"):
        target_mode = "regular"
    elif target_mode in ("gateway", "3p", "openrouter", "proxy"):
        target_mode = "gateway"
    else:
        error(f"Unknown mode '{target_mode}'. Options: 'gateway', 'regular', or 'toggle'.")
        sys.exit(1)

    if current == target_mode:
        info(f"Claude Desktop is ALREADY in {target_mode.upper()} mode.")
        return

    check_claude_closed()

    if target_mode == "regular":
        info("Switching Claude Desktop to REGULAR MODE (Official Anthropic Account)...")
        if os.path.exists(meta_path):
            try:
                with open(meta_path, "r", encoding="utf-8") as f:
                    meta = json.load(f)
                old_id = meta.get("appliedId")
                if old_id:
                    with open(state_file, "w", encoding="utf-8") as sf:
                        sf.write(old_id.strip())
                # Preserve all other profile entries in _meta.json!
                meta["appliedId"] = None
                with open(meta_path, "w", encoding="utf-8") as f:
                    json.dump(meta, f, indent=2)
            except Exception as e:
                warn(f"Could not update _meta.json: {e}")

        # Keep standalone persistent backup in ~/.claude-any-model
        if os.path.exists(state_file):
            try:
                with open(state_file, "r", encoding="utf-8") as sf:
                    cached_id = sf.read().strip()
                cached_profile_path = os.path.join(CLAUDE_3P_DIR, f"{cached_id}.json")
                if os.path.exists(cached_profile_path):
                    shutil.copy2(cached_profile_path, os.path.join(APP_DIR, "gateway_profile.json"))
            except Exception:
                pass

        success("Switched Claude Desktop to REGULAR (Official Anthropic) Mode.")
        print("\033[1;32m[STATUS]\033[0m Claude Desktop will now use your native Anthropic account directly.")
        print("\033[1;36m[PRESERVED]\033[0m All OpenRouter API keys, model mappings, and third-party profiles remain safely stored.\n", file=sys.stderr)
        post_setup_prompt()

    elif target_mode == "gateway":
        info("Switching Claude Desktop to GATEWAY MODE (OpenRouter & Local Inference Proxy)...")
        if platform.system() == "Darwin":
            install_service()

        profile_id = None
        if os.path.exists(state_file):
            try:
                with open(state_file, "r", encoding="utf-8") as sf:
                    profile_id = sf.read().strip()
            except Exception:
                pass

        if not profile_id or not os.path.exists(os.path.join(CLAUDE_3P_DIR, f"{profile_id}.json")):
            if os.path.exists(meta_path):
                try:
                    with open(meta_path, "r", encoding="utf-8") as f:
                        meta = json.load(f)
                    entries = meta.get("entries", [])
                    target_entry = next((e for e in entries if e.get("name") in ("OpenRouter Gateway", "Default")), entries[0] if entries else None)
                    if target_entry:
                        profile_id = target_entry.get("id")
                except Exception:
                    pass

        # Self-heal restore from ~/.claude-any-model/gateway_profile.json if profile JSON was removed
        backup_profile_path = os.path.join(APP_DIR, "gateway_profile.json")
        if profile_id:
            target_profile_path = os.path.join(CLAUDE_3P_DIR, f"{profile_id}.json")
            if not os.path.exists(target_profile_path) and os.path.exists(backup_profile_path):
                try:
                    shutil.copy2(backup_profile_path, target_profile_path)
                    info(f"Self-healed gateway profile {profile_id}.json from persistent backup.")
                except Exception:
                    pass

        if not profile_id or not os.path.exists(os.path.join(CLAUDE_3P_DIR, f"{profile_id}.json")):
            info("No existing profile found. Recreating gateway profile...")
            run_model_configuration()
            return

        if os.path.exists(meta_path):
            try:
                with open(meta_path, "r", encoding="utf-8") as f:
                    meta = json.load(f)
                meta["appliedId"] = profile_id
                entries = meta.get("entries", [])
                if not any(e.get("id") == profile_id for e in entries):
                    entries.append({"id": profile_id, "name": "OpenRouter Gateway"})
                meta["entries"] = entries
                with open(meta_path, "w", encoding="utf-8") as f:
                    json.dump(meta, f, indent=2)
            except Exception as e:
                warn(f"Could not update _meta.json: {e}")

        success(f"Switched Claude Desktop to GATEWAY MODE (Profile ID: {profile_id}).")
        print(f"\033[1;32m[STATUS]\033[0m Claude Desktop is now routed through LiteLLM on http://127.0.0.1:{PORT}\n", file=sys.stderr)
        post_setup_prompt()

def status_service():
    header("Proxy & Claude 3P Status")
    info(f"Curated model recommendations last revisited: {MODELS_LAST_REVISITED}")
    
    # Active mode
    current_mode = get_active_claude_mode()
    if current_mode == "gateway":
        print(f"\033[1;34m[MODE]\033[0m Active Claude Desktop Mode: \033[1;32mGATEWAY MODE (OpenRouter & Local Inference Proxy)\033[0m", file=sys.stderr)
        print("       (Tip: Run \033[1;36m./setup.sh switch regular\033[0m to switch to native Claude Pro/Team)", file=sys.stderr)
    else:
        print(f"\033[1;34m[MODE]\033[0m Active Claude Desktop Mode: \033[1;33mREGULAR MODE (Official Anthropic Account)\033[0m", file=sys.stderr)
        print("       (Tip: Run \033[1;36m./setup.sh switch gateway\033[0m to activate Gateway mode)", file=sys.stderr)

    print("", file=sys.stderr)
    if platform.system() == "Darwin":
        res = subprocess.run(["launchctl", "list", PLIST_LABEL], capture_output=True)
        if res.returncode == 0:
            success(f"Daemon {PLIST_LABEL} (v{VERSION}) is RUNNING.")
        else:
            warn(f"Daemon {PLIST_LABEL} is NOT running.")

    # Check local engines
    local_engines = fetch_local_engines()
    if local_engines:
        for le in local_engines:
            success(f"Local Engine: {le['name']} at {le['api_base']} is ONLINE ({len(le['models'])} model(s) available)")

    # Check .env credentials
    env_path = os.path.join(APP_DIR, ".env")
    has_api_key = False
    if os.path.exists(env_path):
        try:
            with open(env_path, "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("OPENROUTER_API_KEY=") and len(line.split("=", 1)[1].strip()) > 5:
                        has_api_key = True
                        break
        except Exception:
            pass

    if has_api_key:
        success(f"OpenRouter API key is configured in {env_path}")
    else:
        warn(f"No OpenRouter API key found in {env_path} (Only local models will work without an API key).")

    print("", file=sys.stderr)
    info(f"Testing endpoint connectivity on port {PORT}...")
    is_alive = False
    for attempt in range(1, 7):
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{PORT}/health/liveliness")
            with urllib.request.urlopen(req, timeout=2) as resp:
                if resp.status == 200 or b"alive" in resp.read():
                    is_alive = True
                    break
        except Exception:
            pass
        info(f"Waiting for proxy to respond (attempt {attempt}/6)...")
        time.sleep(2)

    if is_alive:
        success(f"Proxy is active and healthy on http://127.0.0.1:{PORT}")
    else:
        warn(f"Could not verify liveliness on http://127.0.0.1:{PORT}. Check logs at {APP_DIR}/logs/litellm.err.log")

    print("", file=sys.stderr)
    meta_path = os.path.join(CLAUDE_3P_DIR, "_meta.json")
    if os.path.exists(meta_path):
        info("Claude 3P Meta Configuration:")
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                print(json.dumps(json.load(f), indent=2), file=sys.stderr)
        except Exception:
            pass

def post_setup_prompt():
    print("", file=sys.stderr)
    if not is_claude_running():
        ans = safe_input("Would you like to open Claude Desktop now? (Y/n): ", "y").lower()
        if ans in ("y", "yes", ""):
            subprocess.run(["open", "-a", "Claude"], check=False)
            success("Claude Desktop launched.")

def usage():
    print(f"Claude Any Model Setup v{VERSION}", file=sys.stderr)
    print("Usage: setup.sh {install|models|switch|status|restart|stop|start|uninstall|version}\n", file=sys.stderr)
    print("Commands:", file=sys.stderr)
    print("  switch [mode] - Easily toggle or switch between 'gateway' and 'regular' (native) Claude mode", file=sys.stderr)
    print("  install       - Full setup: venv, API key, live model selector, Claude 3P config & launchd daemon", file=sys.stderr)
    print("  models        - Live model selector only (updates LiteLLM YAML & Claude 3P config without reinstalling)", file=sys.stderr)
    print("  status        - Checks active mode, launchd daemon status, proxy connectivity, and Claude 3P profiles", file=sys.stderr)
    print("  start         - Starts the launchd daemon", file=sys.stderr)
    print("  stop          - Stops the launchd daemon", file=sys.stderr)
    print("  restart       - Restarts the launchd daemon", file=sys.stderr)
    print("  uninstall     - Unregisters and deletes the launchd startup daemon", file=sys.stderr)
    print("  version       - Displays the current proxy script version", file=sys.stderr)
    sys.exit(1)

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "install"

    if cmd in ("switch", "mode", "toggle"):
        target = sys.argv[2] if len(sys.argv) > 2 else "toggle"
        switch_claude_mode(target)
    elif cmd == "install":
        ensure_dirs()
        setup_env()
        run_model_configuration()
        create_runner_script()
        install_service()
        status_service()
        post_setup_prompt()
    elif cmd == "models":
        ensure_dirs()
        run_model_configuration()
        if platform.system() == "Darwin":
            info("Restarting proxy to apply new YAML configuration...")
            install_service()
            success("Proxy restarted with updated configuration.")
        status_service()
        post_setup_prompt()
    elif cmd == "status":
        status_service()
    elif cmd == "restart":
        ensure_dirs()
        create_runner_script()
        install_service()
        status_service()
    elif cmd == "start":
        subprocess.run(["launchctl", "load", PLIST_PATH], capture_output=True)
        success(f"Started {PLIST_LABEL}")
    elif cmd == "stop":
        subprocess.run(["launchctl", "unload", PLIST_PATH], capture_output=True)
        success("Stopped proxy daemon")
    elif cmd == "uninstall":
        uninstall_service()
    elif cmd in ("version", "--version", "-v"):
        print(f"Claude Any Model v{VERSION}")
    else:
        usage()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\033[1;33m[ABORTED]\033[0m Cancelled by user.", file=sys.stderr)
        sys.exit(130)
