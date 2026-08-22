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
VERSION = "1.12.0"
MODELS_LAST_REVISITED = "2026-08-21"
PORT = 3010
PLIST_LABEL = "com.claude-any-model"
APP_DIR = os.path.expanduser("~/.claude-any-model")
PLIST_PATH = os.path.expanduser(f"~/Library/LaunchAgents/{PLIST_LABEL}.plist")

# All model name strings that clients (Claude Code, Claude Desktop, SDK) may send,
# mapped to the canonical claude_name used in config.yaml.
# Add new aliases here whenever Anthropic ships a new model string.
TIER_ALIASES = {
    # ── OPUS tier ────────────────────────────────────────────────────────────
    "claude-opus-4":              "claude-opus-4",
    "claude-opus-4-5":            "claude-opus-4",
    "claude-opus-5":              "claude-opus-4",
    "claude-opus-latest":         "claude-opus-4",
    "claude-opus":                "claude-opus-4",
    "claude-3-opus-20240229":     "claude-opus-4",
    "claude-3-opus-latest":       "claude-opus-4",
    "claude-3-opus":              "claude-opus-4",

    # ── SONNET tier ──────────────────────────────────────────────────────────
    "claude-sonnet-4-5":              "claude-sonnet-4-5",
    "claude-sonnet-4":                "claude-sonnet-4-5",
    "claude-sonnet-5":                "claude-sonnet-4-5",
    "claude-sonnet-latest":           "claude-sonnet-4-5",
    "claude-sonnet":                  "claude-sonnet-4-5",
    "claude-3-5-sonnet-20241022":     "claude-sonnet-4-5",
    "claude-3-5-sonnet-20240620":     "claude-sonnet-4-5",
    "claude-3-5-sonnet-latest":       "claude-sonnet-4-5",
    "claude-3-5-sonnet":              "claude-sonnet-4-5",
    "claude-3-7-sonnet-20250219":     "claude-sonnet-4-5",
    "claude-3-7-sonnet-latest":       "claude-sonnet-4-5",
    "claude-3-7-sonnet":              "claude-sonnet-4-5",
    "claude-3-sonnet-20240229":       "claude-sonnet-4-5",
    "claude-3-sonnet":                "claude-sonnet-4-5",
    "claude-3-sonnet-latest":         "claude-sonnet-4-5",

    # ── HAIKU tier ───────────────────────────────────────────────────────────
    "claude-3-haiku-20240307":        "claude-3-haiku-20240307",
    "claude-haiku-4":                 "claude-3-haiku-20240307",
    "claude-haiku-4-5":               "claude-3-haiku-20240307",
    "claude-haiku-5":                 "claude-3-haiku-20240307",
    "claude-haiku-latest":            "claude-3-haiku-20240307",
    "claude-haiku":                   "claude-3-haiku-20240307",
    "claude-3-5-haiku-20241022":      "claude-3-haiku-20240307",
    "claude-3-5-haiku-latest":        "claude-3-haiku-20240307",
    "claude-3-5-haiku":               "claude-3-haiku-20240307",
    "claude-3-haiku-latest":          "claude-3-haiku-20240307",
    "claude-3-haiku":                 "claude-3-haiku-20240307",

    # ── FABLE tier ───────────────────────────────────────────────────────────
    "claude-fable-5":                 "claude-fable-5",
    "claude-fable-4":                 "claude-fable-5",
    "claude-fable-latest":            "claude-fable-5",
    "claude-fable":                   "claude-fable-5",

    # ── MYTHOS tier ──────────────────────────────────────────────────────────
    "claude-mythos-1":                "claude-mythos-1",
    "claude-mythos-latest":           "claude-mythos-1",
    "claude-mythos":                  "claude-mythos-1",
}


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
            "User-Agent": "Claude-Any-Model/1.12.0"
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
    """Return sets of installed model name prefixes for each local engine."""
    result = {"ollama": set(), "lmstudio": set(), "vllm": set()}

    # Ollama
    try:
        req = urllib.request.Request("http://localhost:11434/api/tags", headers={"User-Agent": "Claude-Models-Checker"})
        with urllib.request.urlopen(req, timeout=0.8) as resp:
            for m in json.loads(resp.read().decode()).get("models", []):
                result["ollama"].add(m.get("name", ""))
    except Exception:
        pass

    # LM Studio
    try:
        req = urllib.request.Request("http://localhost:1234/v1/models", headers={"User-Agent": "Claude-Models-Checker"})
        with urllib.request.urlopen(req, timeout=0.8) as resp:
            for m in json.loads(resp.read().decode()).get("data", []):
                result["lmstudio"].add(m.get("id", ""))
    except Exception:
        pass

    # vLLM / llama.cpp
    try:
        req = urllib.request.Request("http://localhost:8000/v1/models", headers={"User-Agent": "Claude-Models-Checker"})
        with urllib.request.urlopen(req, timeout=0.8) as resp:
            for m in json.loads(resp.read().decode()).get("data", []):
                result["vllm"].add(m.get("id", ""))
    except Exception:
        pass

    return result

def get_ollama_ctx(model_name):
    """Query Ollama /api/show for a model's context length."""
    try:
        payload = json.dumps({"model": model_name}).encode()
        req = urllib.request.Request(
            "http://localhost:11434/api/show",
            data=payload,
            headers={"Content-Type": "application/json", "User-Agent": "Claude-Models-Checker"},
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=2) as r:
            info_data = json.loads(r.read().decode())
            ctx = (
                info_data.get("model_info", {}).get("llm.context_length") or
                info_data.get("model_info", {}).get("context_length") or
                info_data.get("details", {}).get("context_length")
            )
            if not ctx:
                for line in info_data.get("parameters", "").splitlines():
                    if "num_ctx" in line:
                        parts = line.split()
                        if len(parts) >= 2 and parts[-1].isdigit():
                            ctx = int(parts[-1])
                            break
            if ctx:
                ctx = int(ctx)
                if ctx >= 1_000_000:
                    return f"{ctx // 1_000_000}M Context", True
                elif ctx >= 1_000:
                    return f"{ctx // 1_000}k Context", ctx >= 900_000
    except Exception:
        pass
    return "Local Context", False


def fetch_openrouter_catalog():
    info("Fetching live model catalog & pricing from OpenRouter API...")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/models",
        headers={"User-Agent": "Claude-Any-Model/1.12.0"}
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
    installed = fetch_local_engines()  # dict: {"ollama": set(), "lmstudio": set(), "vllm": set()}

    ollama_installed = installed.get("ollama", set())
    if ollama_installed:
        info(f"Ollama: {len(ollama_installed)} model(s) installed")

    # Helper: build an Ollama option entry if the model is installed
    def ollama_opt(model_id, label, ctx_str="Local Context", supports1m=False, is_recommended=False):
        # Match against installed names (exact or prefix, e.g. "qwen3-coder:32b" or "qwen3-coder")
        matched = next((n for n in ollama_installed if n == model_id or n.startswith(model_id + ":")), None)
        if not matched:
            return None
        ctx_display, s1m = get_ollama_ctx(matched)
        return {
            "id": f"ollama/{matched}",
            "raw_model_id": matched,
            "name": label,
            "price_str": "$0.00 / Local",
            "ctx_str": ctx_display,
            "supports1m": s1m or supports1m,
            "provider": "ollama",
            "api_base": "http://localhost:11434",
            "is_recommended": is_recommended,
        }

    def ollama_opts(entries):
        return [o for o in (ollama_opt(*e) if not isinstance(e, dict) else e for e in entries) if o]

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
            ],
            "ollama_options": ollama_opts([
                ("llama3.3", "llama3.3:70b", "Local Context", True, True),
                ("qwen2.5", "qwen2.5:72b", "Local Context", True),
                ("deepseek-r1", "deepseek-r1:70b", "Local Context", True),
                ("mixtral:8x22b", "mixtral:8x22b", "Local Context", False),
                ("nemotron", "nemotron:70b", "Local Context", True),
                ("command-r-plus", "command-r-plus:104b", "Local Context", True),
            ]),
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
            ],
            "ollama_options": ollama_opts([
                ("qwen2.5-coder:32b", "qwen2.5-coder:32b", "Local Context", False, True),
                ("qwen2.5-coder:14b", "qwen2.5-coder:14b", "Local Context", False),
                ("deepseek-coder-v2", "deepseek-coder-v2:16b", "Local Context", False),
                ("codellama:34b", "codellama:34b", "Local Context", False),
                ("mixtral:8x7b", "mixtral:8x7b", "Local Context", False),
                ("mistral-nemo", "mistral-nemo:12b", "Local Context", False),
                ("llama3.1:8b", "llama3.1:8b", "Local Context", False),
                ("gemma2:9b", "gemma2:9b", "Local Context", False),
                ("phi4", "phi4:14b", "Local Context", False),
            ]),
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
            ],
            "ollama_options": ollama_opts([
                ("qwen2.5-coder:7b", "qwen2.5-coder:7b", "Local Context", False, True),
                ("deepseek-coder:6.7b", "deepseek-coder:6.7b", "Local Context", False),
                ("phi3:mini", "phi3:mini", "Local Context", False),
                ("phi3.5:mini", "phi3.5:mini", "Local Context", False),
                ("gemma2:2b", "gemma2:2b", "Local Context", False),
                ("llama3.2:3b", "llama3.2:3b", "Local Context", False),
                ("qwen2.5:7b", "qwen2.5:7b", "Local Context", False),
                ("mistral:7b", "mistral:7b", "Local Context", False),
            ]),
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
            ],
            "ollama_options": ollama_opts([
                ("qwen2.5-coder:32b", "qwen2.5-coder:32b", "Local Context", False, True),
                ("llama3.3", "llama3.3:70b", "Local Context", True),
                ("deepseek-r1:32b", "deepseek-r1:32b", "Local Context", False),
                ("codellama:34b", "codellama:34b", "Local Context", False),
            ]),
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
            ],
            "ollama_options": ollama_opts([
                ("deepseek-r1:671b", "deepseek-r1:671b", "Local Context", True, True),
                ("llama3.1:405b", "llama3.1:405b", "Local Context", True),
                ("nemotron:340b", "nemotron:340b", "Local Context", True),
            ]),
        },
    ]

    header(f"Configure Inference Models for Claude Desktop (Curated: {MODELS_LAST_REVISITED})")
    print(f"\033[1;34m[INFO]\033[0m Curated model list last revisited: \033[1;36m{MODELS_LAST_REVISITED}\033[0m", file=sys.stderr)
    print("Select your target model for each Anthropic family tier.", file=sys.stderr)
    print("Supports OpenRouter cloud models and local engines (Ollama, LM Studio, vLLM).\n", file=sys.stderr)

    selections = []

    for idx, t in enumerate(tiers, 1):
        print(f"\033[1;35m--- [{idx}/5] {t['tier_label']} ---\033[0m", file=sys.stderr)

        current_model_id = current_config.get(t["claude_name"])
        matched_current_idx = None
        recommended_idx = 1

        # OpenRouter curated options + matching installed Ollama models
        all_options = list(t["options"]) + list(t.get("ollama_options", []))

        # Print OpenRouter cloud section
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

        # Print Ollama curated section (only installed models)
        ollama_opts_for_tier = [o for o in all_options if o.get("provider") == "ollama"]
        if ollama_opts_for_tier:
            print(f"  \033[1;36m⬡  Ollama (Local)\033[0m", file=sys.stderr)
        for opt_idx, opt in enumerate(all_options, 1):
            if opt.get("provider") != "ollama":
                continue
            is_current = (current_model_id is not None and (opt["id"] == current_model_id or opt.get("raw_model_id") == current_model_id))
            if is_current:
                matched_current_idx = opt_idx
            if opt.get("is_recommended") and matched_current_idx is None:
                recommended_idx = opt_idx
            tags = []
            if opt.get("is_recommended"):
                tags.append("\033[1;32m(Recommended)\033[0m")
            if is_current:
                tags.append("\033[1;33m[CURRENT]\033[0m")
            tag_str = f"  {' '.join(tags)}" if tags else ""
            print(f"  {opt_idx}) {opt['raw_model_id']:<26} $0.00 / Local   [{opt['ctx_str']}]{tag_str}", file=sys.stderr)

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
    canonical_names = {s["claude_name"] for s in selections}

    # Build the full allowed set: canonical names + every alias that maps to a configured tier
    allowed_models = sorted(
        {alias for alias, canon in TIER_ALIASES.items() if canon in canonical_names} | canonical_names
    )

    guardrail_py_path = os.path.join(APP_DIR, "guardrail.py")
    guardrail_code = f"""# Strict Model Guardrail - auto-generated by setup.sh
# Allows all known Claude model aliases that map to a configured tier.
from litellm.integrations.custom_logger import CustomLogger
from fastapi import HTTPException

ALLOWED_MODELS = set({json.dumps(allowed_models)})

# Alias map: any incoming model name is normalised to its canonical tier name
ALIAS_MAP = {{k: v for k, v in {json.dumps(dict(TIER_ALIASES))}.items() if v in {json.dumps(sorted(canonical_names))}}}

class StrictModelGuardrail(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type, **kwargs):
        requested_model = data.get("model")
        if requested_model:
            canonical = ALIAS_MAP.get(requested_model, requested_model)
            if canonical not in ALLOWED_MODELS:
                raise HTTPException(
                    status_code=403,
                    detail=f"[Strict Guardrail] Model '{{requested_model}}' is not permitted. "
                           f"Configured tiers: {{sorted(set(ALIAS_MAP.values()))}}",
                )
            # Rewrite to canonical name so LiteLLM routes correctly
            data["model"] = canonical
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
        # Collect every alias that maps to this tier's canonical name
        aliases = sorted({alias for alias, canon in TIER_ALIASES.items() if canon == s["claude_name"]})
        if not aliases:
            aliases = [s["claude_name"]]

        def litellm_params(lines, s):
            if s["provider"] == "openrouter":
                lines.append(f"      model: openrouter/{s['model_id']}")
                lines.append(f"      api_key: os.environ/OPENROUTER_API_KEY")
            elif s["provider"] == "ollama":
                raw_id = s['model_id'][len("ollama/"):] if s['model_id'].startswith("ollama/") else s['model_id']
                lines.append(f"      model: ollama/{raw_id}")
                lines.append(f"      api_base: {s['api_base'] or 'http://localhost:11434'}")
            elif s["provider"] in ("openai", "lmstudio", "vllm"):
                raw_id = s['model_id'][len("openai/"):] if s['model_id'].startswith("openai/") else s['model_id']
                lines.append(f"      model: openai/{raw_id}")
                lines.append(f"      api_base: {s['api_base'] or 'http://localhost:1234/v1'}")
                lines.append(f"      api_key: dummy-key")
            else:
                lines.append(f"      model: {s['model_id']}")
                if s.get("api_base"):
                    lines.append(f"      api_base: {s['api_base']}")
                lines.append(f"      api_key: dummy-key")

        yaml_lines.append(f"  # ── {s['tier'].capitalize()} tier → {s['label']}")
        for alias in aliases:
            yaml_lines.append(f"  - model_name: {alias}")
            yaml_lines.append(f"    litellm_params:")
            litellm_params(yaml_lines, s)
            yaml_lines.append("")


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
        "allowedEgressHosts": ["*"],
        "coworkEgressAllowedHosts": ["*"],
        # Features & surfaces enabled
        "isClaudeCodeForDesktopEnabled": True,
        "coworkTabEnabled": True,
        "chatTabEnabled": True,
        "chatAdvancedFileAnalysisEnabled": True,
        "isDesktopExtensionEnabled": True,
        "isLocalDevMcpEnabled": True,
        "mcpPersistentAlwaysAllowEnabled": True,
        "autoModeEnabled": True,
        "skillCreationEnabled": True,
        "disableBundledSkills": False,
        "disabledBuiltinTools": [],
        "builtinToolPolicy": {
            "Bash": "allow",
            "Read": "allow",
            "Write": "allow",
            "Edit": "allow",
            "Glob": "allow",
            "Grep": "allow",
            "NotebookEdit": "allow",
            "WebFetch": "allow",
            "WebSearch": "allow",
            "Task": "allow",
            "TodoWrite": "allow",
            "TaskCreate": "allow",
            "TaskUpdate": "allow",
            "TaskGet": "allow",
            "TaskList": "allow",
            "TaskStop": "allow",
            "Skill": "allow",
            "REPL": "allow",
            "JavaScript": "allow",
            "AskUserQuestion": "allow",
            "ToolSearch": "allow",
            "SendUserMessage": "allow"
        },
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

# Use uv run to avoid stale shebang issues when venv was built elsewhere.
# Falls back to activating the venv directly if uv is not on PATH.
if command -v uv &>/dev/null; then
    exec uv run --project "$APP_DIR" litellm --config "$APP_DIR/config.yaml" --port {PORT} --host 127.0.0.1
else
    source "$APP_DIR/venv/bin/activate"
    exec litellm --config "$APP_DIR/config.yaml" --port {PORT} --host 127.0.0.1
fi
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

def _detect_account_uuid(config_path):
    """Extract account UUID from a claude_desktop_config.json's epitaxyPrefs keys."""
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        epi = cfg.get("preferences", {}).get("epitaxyPrefs", {})
        for key in epi:
            if key.startswith("epitaxy-perm-mode-acks."):
                return key.split(".")[-1]
    except Exception:
        pass
    return None

def _scan_session_dir(sessions_root, account_uuid):
    """Scan a claude-code-sessions directory for session JSON files.

    Returns {sessionId: {"path": path, "lastActivityAt": int, "data": dict}}.
    """
    sessions = {}
    if not account_uuid:
        return sessions
    account_dir = os.path.join(sessions_root, account_uuid)
    if not os.path.isdir(account_dir):
        return sessions
    for workspace in os.listdir(account_dir):
        ws_dir = os.path.join(account_dir, workspace)
        if not os.path.isdir(ws_dir):
            continue
        for fname in os.listdir(ws_dir):
            if not fname.endswith(".json"):
                continue
            fpath = os.path.join(ws_dir, fname)
            try:
                with open(fpath, "r", encoding="utf-8") as f:
                    data = json.load(f)
                sid = data.get("sessionId")
                if not sid:
                    continue
                last_activity = data.get("lastActivityAt", 0)
                sessions[sid] = {
                    "path": fpath,
                    "lastActivityAt": last_activity,
                    "data": data,
                    "workspace": workspace,
                }
            except Exception:
                pass
    return sessions

def _read_group_scopes(config_path):
    """Read dframe-group-scopes and starred sessions from a claude_desktop_config.json."""
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        epi = cfg.get("preferences", {}).get("epitaxyPrefs", {})
        return {
            "dframe-group-scopes": epi.get("dframe-group-scopes", {}),
            "starred-local-code-sessions": set(epi.get("starred-local-code-sessions", [])),
        }
    except Exception:
        return {"dframe-group-scopes": {}, "starred-local-code-sessions": set()}

def sync_sessions():
    """Two-way merge of session metadata and sidebar groupings between 1P and 3P modes.

    Merges by sessionId (newer lastActivityAt wins on conflict).
    Unions group assignments and starred sessions (account-agnostic keys).
    Shows a stats preview and prompts before making changes.
    """
    claude_1p_support = os.path.expanduser("~/Library/Application Support/Claude")
    claude_3p_support = os.path.expanduser("~/Library/Application Support/Claude-3p")
    cfg_1p = os.path.join(claude_1p_support, "claude_desktop_config.json")
    cfg_3p = os.path.join(claude_3p_support, "claude_desktop_config.json")
    sessions_1p_root = os.path.join(claude_1p_support, "claude-code-sessions")
    sessions_3p_root = os.path.join(claude_3p_support, "claude-code-sessions")

    acct_1p = _detect_account_uuid(cfg_1p)
    acct_3p = _detect_account_uuid(cfg_3p)

    if not acct_1p and not acct_3p:
        warn("Could not detect account UUIDs from either claude_desktop_config.json.")
        warn("Make sure Claude Desktop has been launched at least once in both modes.")
        return

    header("Session Sync (1P ↔ 3P)")

    sessions_1p = _scan_session_dir(sessions_1p_root, acct_1p)
    sessions_3p = _scan_session_dir(sessions_3p_root, acct_3p)

    all_sids = set(sessions_1p.keys()) | set(sessions_3p.keys())
    only_1p = []
    only_3p = []
    updated = []
    unchanged = 0

    for sid in all_sids:
        in_1p = sid in sessions_1p
        in_3p = sid in sessions_3p
        if in_1p and not in_3p:
            only_1p.append(sid)
        elif in_3p and not in_1p:
            only_3p.append(sid)
        else:
            t1 = sessions_1p[sid]["lastActivityAt"]
            t3 = sessions_3p[sid]["lastActivityAt"]
            if t1 > t3:
                updated.append((sid, "1p→3p"))
            elif t3 > t1:
                updated.append((sid, "3p→1p"))
            else:
                unchanged += 1

    # Compute group assignment merge
    groups_1p = _read_group_scopes(cfg_1p)
    groups_3p = _read_group_scopes(cfg_3p)

    new_assignments_1p = 0
    new_assignments_3p = 0
    for scope_key in set(groups_1p["dframe-group-scopes"].keys()) | set(groups_3p["dframe-group-scopes"].keys()):
        a1 = groups_1p["dframe-group-scopes"].get(scope_key, {}).get("assignments", {})
        a3 = groups_3p["dframe-group-scopes"].get(scope_key, {}).get("assignments", {})
        new_assignments_1p += len(set(a3.keys()) - set(a1.keys()))
        new_assignments_3p += len(set(a1.keys()) - set(a3.keys()))

    new_starred_1p = len(groups_3p["starred-local-code-sessions"] - groups_1p["starred-local-code-sessions"])
    new_starred_3p = len(groups_1p["starred-local-code-sessions"] - groups_3p["starred-local-code-sessions"])

    total_actions = len(only_1p) + len(only_3p) + len(updated) + new_assignments_1p + new_assignments_3p + new_starred_1p + new_starred_3p

    if total_actions == 0:
        success("Sessions and groupings are already in sync. No changes needed.")
        return

    print("", file=sys.stderr)
    print(f"  Sessions only in Gateway (3P):     {len(only_3p):>4}  → will copy to Regular (1P)", file=sys.stderr)
    print(f"  Sessions only in Regular (1P):    {len(only_1p):>4}  → will copy to Gateway (3P)", file=sys.stderr)
    print(f"  Sessions updated (newer activity): {len(updated):>4}  → will overwrite older copy", file=sys.stderr)
    print(f"  Sessions unchanged:                {unchanged:>4}  → no action", file=sys.stderr)
    print("", file=sys.stderr)
    print(f"  Group assignments to merge:        {new_assignments_1p + new_assignments_3p:>4}  new → will add to both", file=sys.stderr)
    print(f"  Starred sessions to merge:          {new_starred_1p + new_starred_3p:>4}  new → will add to both", file=sys.stderr)
    print("", file=sys.stderr)

    ans = safe_input("Sync sessions between modes? (Y/n): ", "y").lower()
    if ans not in ("y", "yes", ""):
        info("Session sync skipped.")
        return

    # ── Execute: copy session files ───────────────────────────────────────────
    def _ensure_target_dir(sessions_root, account_uuid, workspace):
        d = os.path.join(sessions_root, account_uuid, workspace)
        os.makedirs(d, exist_ok=True)
        return d

    # Copy 1P-only → 3P
    for sid in only_1p:
        src = sessions_1p[sid]
        target_dir = _ensure_target_dir(sessions_3p_root, acct_3p, src["workspace"])
        target_path = os.path.join(target_dir, os.path.basename(src["path"]))
        shutil.copy2(src["path"], target_path)

    # Copy 3P-only → 1P
    for sid in only_3p:
        src = sessions_3p[sid]
        target_dir = _ensure_target_dir(sessions_1p_root, acct_1p, src["workspace"])
        target_path = os.path.join(target_dir, os.path.basename(src["path"]))
        shutil.copy2(src["path"], target_path)

    # Update conflicting sessions (newer wins)
    for sid, direction in updated:
        if direction == "1p→3p":
            src = sessions_1p[sid]
            target_dir = _ensure_target_dir(sessions_3p_root, acct_3p, src["workspace"])
            shutil.copy2(src["path"], os.path.join(target_dir, os.path.basename(src["path"])))
        else:
            src = sessions_3p[sid]
            target_dir = _ensure_target_dir(sessions_1p_root, acct_1p, src["workspace"])
            shutil.copy2(src["path"], os.path.join(target_dir, os.path.basename(src["path"])))

    # ── Execute: merge group assignments ─────────────────────────────────────
    for config_path, groups_local, groups_remote, acct_local in [
        (cfg_1p, groups_1p, groups_3p, acct_1p),
        (cfg_3p, groups_3p, groups_1p, acct_3p),
    ]:
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            epi = cfg.setdefault("preferences", {}).setdefault("epitaxyPrefs", {})

            # Merge dframe-group-scopes
            local_scopes = epi.get("dframe-group-scopes", {})
            for scope_key in set(local_scopes.keys()) | set(groups_remote["dframe-group-scopes"].keys()):
                local_scope = local_scopes.get(scope_key, {"groups": [], "assignments": {}})
                remote_scope = groups_remote["dframe-group-scopes"].get(scope_key, {"groups": [], "assignments": {}})
                # Union groups (dedupe by group id)
                local_groups = local_scope.get("groups", [])
                remote_groups = remote_scope.get("groups", [])
                seen_ids = {g.get("id") for g in local_groups}
                for g in remote_groups:
                    if g.get("id") not in seen_ids:
                        local_groups.append(g)
                        seen_ids.add(g.get("id"))
                local_scope["groups"] = local_groups
                # Union assignments
                local_scope.setdefault("assignments", {}).update(remote_scope.get("assignments", {}))
                local_scopes[scope_key] = local_scope
            epi["dframe-group-scopes"] = local_scopes

            # Merge starred sessions
            local_starred = set(epi.get("starred-local-code-sessions", []))
            local_starred.update(groups_remote["starred-local-code-sessions"])
            epi["starred-local-code-sessions"] = sorted(local_starred)

            with open(config_path, "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2)
        except Exception as e:
            warn(f"Could not update {config_path}: {e}")

    success("Session sync complete.")

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
        remove_sandbox_network_config()
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
        sync_sessions()
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
            configure_sandbox_network()
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
        configure_sandbox_network()
        sync_sessions()
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
    engine_labels = {"ollama": ("Ollama", "http://localhost:11434"), "lmstudio": ("LM Studio", "http://localhost:1234/v1"), "vllm": ("vLLM", "http://localhost:8000/v1")}
    for key, names in local_engines.items():
        if names:
            label, url = engine_labels.get(key, (key, ""))
            success(f"Local Engine: {label} at {url} is ONLINE ({len(names)} model(s) installed)")

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

def configure_sandbox_network():
    """Offer to configure the network egress allowlist for the embedded Claude Code agent.

    Gateway mode enforces a strict network sandbox by default — only the inference
    endpoint (127.0.0.1) and api.anthropic.com are reachable. This makes gh CLI,
    curl, npx, npm install, web search from Bash, and similar tools fail with 403.

    The allowlist is controlled by the 'allowedEgressHosts' key in the gateway
    profile JSON (not ~/.claude/settings.json, which is ignored in gateway mode).
    run_model_configuration() already writes allowedEgressHosts: ["*"] into the
    profile. This function handles the case where the profile already exists but
    lacks the key (e.g. upgrading from an older setup.sh version), and also sets
    it in claude_desktop_config.json preferences as a belt-and-suspenders measure.
    """
    marker_path = os.path.join(APP_DIR, ".egress_configured")
    if os.path.exists(marker_path):
        return

    print("", file=sys.stderr)
    print("\033[1;36m[NETWORK]\033[0m Gateway mode enforces a strict network sandbox by default.", file=sys.stderr)
    print("         This blocks outbound network from Bash commands — gh CLI, curl, npx,", file=sys.stderr)
    print("         npm install, web search, and similar tools all fail with 403 errors.", file=sys.stderr)
    print("         Allowing all egress hosts restores full network access from Bash commands.", file=sys.stderr)
    print("", file=sys.stderr)

    ans = safe_input("Configure network egress to allow all hosts? (Y/n): ", "y").lower()
    if ans not in ("y", "yes", ""):
        info("Skipping network egress configuration. Bash commands will have restricted network access in Gateway mode.")
        return

    _set_egress_allowlist(["*"])
    with open(marker_path, "w", encoding="utf-8") as f:
        f.write("1")
    success("Network egress configured to allow all hosts.")


def _set_egress_allowlist(hosts):
    """Set egress allowlist keys in the live gateway profile and claude_desktop_config.json.

    Writes both 'allowedEgressHosts' (profile-level, read by the Desktop host's
    vmEgressPolicy) and 'coworkEgressAllowedHosts' (workspace-level, translated
    into the CLI subprocess network sandbox allowlist at spawn time). Both must
    be present; the host enforces the stricter of the two.
    """
    # Update the live gateway profile(s)
    meta_path = os.path.join(CLAUDE_3P_DIR, "_meta.json")
    profile_ids = []
    if os.path.exists(meta_path):
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                meta = json.load(f)
            applied_id = meta.get("appliedId")
            if applied_id:
                profile_ids.append(applied_id)
            for entry in meta.get("entries", []):
                eid = entry.get("id")
                if eid and eid not in profile_ids:
                    profile_ids.append(eid)
        except Exception:
            pass

    for pid in profile_ids:
        profile_path = os.path.join(CLAUDE_3P_DIR, f"{pid}.json")
        if os.path.exists(profile_path):
            try:
                with open(profile_path, "r", encoding="utf-8") as f:
                    profile = json.load(f)
                profile["allowedEgressHosts"] = hosts
                profile["coworkEgressAllowedHosts"] = hosts
                with open(profile_path, "w", encoding="utf-8") as f:
                    json.dump(profile, f, indent=2)
            except Exception:
                pass

    # Update the persistent backup copy
    backup_path = os.path.join(APP_DIR, "gateway_profile.json")
    if os.path.exists(backup_path):
        try:
            with open(backup_path, "r", encoding="utf-8") as f:
                backup = json.load(f)
            backup["allowedEgressHosts"] = hosts
            backup["coworkEgressAllowedHosts"] = hosts
            with open(backup_path, "w", encoding="utf-8") as f:
                json.dump(backup, f, indent=2)
        except Exception:
            pass

    # Also set in claude_desktop_config.json preferences
    desktop_config_path = os.path.expanduser("~/Library/Application Support/Claude-3p/claude_desktop_config.json")
    if os.path.exists(desktop_config_path):
        try:
            with open(desktop_config_path, "r", encoding="utf-8") as f:
                desktop_cfg = json.load(f)
            prefs = desktop_cfg.setdefault("preferences", {})
            prefs["allowedEgressHosts"] = hosts
            prefs["coworkEgressAllowedHosts"] = hosts
            with open(desktop_config_path, "w", encoding="utf-8") as f:
                json.dump(desktop_cfg, f, indent=2)
        except Exception:
            pass


def remove_sandbox_network_config():
    """Remove the allowedEgressHosts config added by configure_sandbox_network().

    Removes the key from the live gateway profile, the persistent backup, and
    claude_desktop_config.json preferences. This restores the default sandbox
    behavior (only inference endpoint + api.anthropic.com reachable).
    """
    marker_path = os.path.join(APP_DIR, ".egress_configured")

    # Remove allowedEgressHosts from all gateway profiles
    meta_path = os.path.join(CLAUDE_3P_DIR, "_meta.json")
    profile_ids = []
    if os.path.exists(meta_path):
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                meta = json.load(f)
            applied_id = meta.get("appliedId")
            if applied_id:
                profile_ids.append(applied_id)
            for entry in meta.get("entries", []):
                eid = entry.get("id")
                if eid and eid not in profile_ids:
                    profile_ids.append(eid)
        except Exception:
            pass

    for pid in profile_ids:
        profile_path = os.path.join(CLAUDE_3P_DIR, f"{pid}.json")
        if os.path.exists(profile_path):
            try:
                with open(profile_path, "r", encoding="utf-8") as f:
                    profile = json.load(f)
                profile.pop("allowedEgressHosts", None)
                profile.pop("coworkEgressAllowedHosts", None)
                with open(profile_path, "w", encoding="utf-8") as f:
                    json.dump(profile, f, indent=2)
            except Exception:
                pass

    # Remove from persistent backup
    backup_path = os.path.join(APP_DIR, "gateway_profile.json")
    if os.path.exists(backup_path):
        try:
            with open(backup_path, "r", encoding="utf-8") as f:
                backup = json.load(f)
            backup.pop("allowedEgressHosts", None)
            backup.pop("coworkEgressAllowedHosts", None)
            with open(backup_path, "w", encoding="utf-8") as f:
                json.dump(backup, f, indent=2)
        except Exception:
            pass

    # Remove from claude_desktop_config.json preferences
    desktop_config_path = os.path.expanduser("~/Library/Application Support/Claude-3p/claude_desktop_config.json")
    if os.path.exists(desktop_config_path):
        try:
            with open(desktop_config_path, "r", encoding="utf-8") as f:
                desktop_cfg = json.load(f)
            desktop_cfg.get("preferences", {}).pop("allowedEgressHosts", None)
            desktop_cfg.get("preferences", {}).pop("coworkEgressAllowedHosts", None)
            with open(desktop_config_path, "w", encoding="utf-8") as f:
                json.dump(desktop_cfg, f, indent=2)
        except Exception:
            pass

    try:
        os.remove(marker_path)
    except Exception:
        pass

    success("Removed network egress configuration. Sandbox restrictions restored to default.")


def launch_claude_cli(extra_args=None):
    """Launch Claude CLI with ANTHROPIC_BASE_URL pointing at the local proxy."""
    env = os.environ.copy()
    env["ANTHROPIC_BASE_URL"] = f"http://127.0.0.1:{PORT}"
    env["ANTHROPIC_API_KEY"] = "dummy-key"
    # Load .env for any extra vars (OPENROUTER_API_KEY, etc.)
    env_path = os.path.join(APP_DIR, ".env")
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, _, v = line.partition("=")
                    env.setdefault(k.strip(), v.strip())

    claude_bin = shutil.which("claude")
    if not claude_bin:
        error("'claude' binary not found on PATH. Install Claude Code: https://claude.ai/code")
        sys.exit(1)

    info(f"Launching Claude CLI → proxy on http://127.0.0.1:{PORT}")
    cmd = [claude_bin] + (extra_args or [])
    os.execve(claude_bin, cmd, env)

def post_setup_prompt():
    print("", file=sys.stderr)
    info(f"Launch Claude CLI via proxy:  ./setup.sh launch")
    info(f"  — or manually: ANTHROPIC_BASE_URL=http://127.0.0.1:{PORT} ANTHROPIC_API_KEY=dummy-key claude")

    if not is_claude_running():
        ans = safe_input("Would you like to open Claude Desktop now? (Y/n): ", "y").lower()
        if ans in ("y", "yes", ""):
            subprocess.run(["open", "-a", "Claude"], check=False)
            success("Claude Desktop launched.")

def usage():
    print(f"Claude Any Model Setup v{VERSION}", file=sys.stderr)
    print("Usage: setup.sh {install|models|switch|launch|status|restart|stop|start|uninstall|version}\n", file=sys.stderr)
    print("Commands:", file=sys.stderr)
    print("  switch [mode]  - Toggle or switch between 'gateway' and 'regular' (native) Claude mode", file=sys.stderr)
    print("  launch [args]  - Launch Claude CLI routed through the local proxy (sets ANTHROPIC_BASE_URL)", file=sys.stderr)
    print("  install        - Full setup: venv, API key, live model selector, Claude 3P config & launchd daemon", file=sys.stderr)
    print("  models         - Live model selector only (updates LiteLLM YAML & Claude 3P config without reinstalling)", file=sys.stderr)
    print("  status         - Checks active mode, launchd daemon status, proxy connectivity, and Claude 3P profiles", file=sys.stderr)
    print("  start          - Starts the launchd daemon", file=sys.stderr)
    print("  stop           - Stops the launchd daemon", file=sys.stderr)
    print("  restart        - Restarts the launchd daemon", file=sys.stderr)
    print("  uninstall      - Unregisters launchd daemon", file=sys.stderr)
    print("  sync-sessions  - Merge session metadata and sidebar groupings between 1P and 3P modes", file=sys.stderr)
    print("  version        - Displays the current proxy script version", file=sys.stderr)
    sys.exit(1)

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "install"

    if cmd in ("switch", "mode", "toggle"):
        target = sys.argv[2] if len(sys.argv) > 2 else "toggle"
        switch_claude_mode(target)
    elif cmd in ("sync-sessions", "sync"):
        sync_sessions()
    elif cmd in ("launch", "run"):
        launch_claude_cli(extra_args=sys.argv[2:])
    elif cmd == "install":
        ensure_dirs()
        setup_env()
        run_model_configuration()
        create_runner_script()
        install_service()
        configure_sandbox_network()
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
        remove_sandbox_network_config()
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
