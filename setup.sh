#!/usr/bin/env bash
""":"
# ==============================================================================
# 🐍💀 Bash/Python Polyglot Bootstrapper (Pymera + uv pattern)
# Uses uv to ensure managed Python (3.12) & virtualenv exist with LiteLLM,
# then seamlessly re-executes this file as a Python program.
# ==============================================================================
set -euo pipefail

APP_DIR="${HOME}/.claude-openrouter-models"
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
    curl -fsSL https://raw.githubusercontent.com/axiomantic/claude-openrouter-models/main/setup.sh -o "${SCRIPT_PATH}" 2>/dev/null || true
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
# 🚀 Claude OpenRouter Models — Python Implementation
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
VERSION = "1.2.0"
MODELS_LAST_REVISITED = "2026-08-21"
PORT = 3010
PLIST_LABEL = "com.claude-openrouter-models"
LEGACY_PLIST_LABELS = ["com.claude-to-openrouter-proxy", "com.litellm.proxy"]

APP_DIR = os.path.expanduser("~/.claude-openrouter-models")
LEGACY_APP_DIRS = [
    os.path.expanduser("~/.claude-to-openrouter-proxy"),
    os.path.expanduser("~/.litellm-proxy"),
]
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

def migrate_legacy_dirs():
    os.makedirs(APP_DIR, exist_ok=True)
    os.makedirs(os.path.join(APP_DIR, "logs"), exist_ok=True)
    os.makedirs(CLAUDE_3P_DIR, exist_ok=True)
    launch_agents = os.path.expanduser("~/Library/LaunchAgents")
    if platform.system() == "Darwin":
        os.makedirs(launch_agents, exist_ok=True)

    for legacy in LEGACY_APP_DIRS:
        if os.path.exists(legacy) and not os.path.islink(legacy):
            info(f"Migrating legacy directory from {legacy} to {APP_DIR}...")
            # Copy all files
            for item in os.listdir(legacy):
                src = os.path.join(legacy, item)
                dst = os.path.join(APP_DIR, item)
                if not os.path.exists(dst):
                    if os.path.isdir(src):
                        shutil.copytree(src, dst)
                    else:
                        shutil.copy2(src, dst)
            shutil.rmtree(legacy)
            try:
                os.symlink(APP_DIR, legacy)
                success(f"Moved {legacy} -> {APP_DIR} and created compatibility symlink.")
            except Exception:
                pass
        elif not os.path.exists(legacy):
            try:
                os.symlink(APP_DIR, legacy)
            except Exception:
                pass

    if platform.system() == "Darwin":
        for legacy_label in LEGACY_PLIST_LABELS:
            legacy_plist = os.path.expanduser(f"~/Library/LaunchAgents/{legacy_label}.plist")
            if os.path.exists(legacy_plist):
                info(f"Unloading legacy launchd daemon ({legacy_label})...")
                subprocess.run(["launchctl", "unload", legacy_plist], capture_output=True)
                try:
                    os.remove(legacy_plist)
                except Exception:
                    pass

def is_claude_running():
    try:
        res = subprocess.run(["pgrep", "-i", "Claude"], capture_output=True, text=True)
        return res.returncode == 0
    except Exception:
        return False

def check_claude_closed():
    running = False
    while is_claude_running():
        running = True
        print("", file=sys.stderr)
        warn("Claude Desktop is currently RUNNING.")
        print("\033[1;33m[ACTION REQUIRED]\033[0m Please quit Claude Desktop (Cmd+Q) to safely apply configuration.", file=sys.stderr)
        safe_input("Press [Enter] once Claude Desktop has exited (or Ctrl+C to abort)...", "")

    if running:
        success("Claude Desktop is closed. Proceeding...")

def validate_openrouter_key(api_key):
    info("Validating OpenRouter API key...")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/auth/key",
        headers={"Authorization": f"Bearer {api_key}", "User-Agent": "Claude-OpenRouter-Models/1.2.0"}
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            if resp.status == 200:
                success("OpenRouter API key verified successfully.")
                return True
    except Exception as e:
        warn(f"Could not verify OpenRouter key ({e}). Proceeding anyway in case of offline/firewall restrictions.")
    return True

def find_existing_api_key():
    # 1. Check current .env
    env_path = os.path.join(APP_DIR, ".env")
    if os.path.exists(env_path):
        try:
            with open(env_path, "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("OPENROUTER_API_KEY="):
                        val = line.split("=", 1)[1].strip()
                        if len(val) > 5:
                            return val
        except Exception:
            pass

    # 2. Check legacy app dirs
    for leg in LEGACY_APP_DIRS:
        leg_env = os.path.join(leg, ".env")
        if os.path.exists(leg_env):
            try:
                with open(leg_env, "r", encoding="utf-8") as f:
                    for line in f:
                        if line.startswith("OPENROUTER_API_KEY="):
                            val = line.split("=", 1)[1].strip()
                            if len(val) > 5:
                                return val
            except Exception:
                pass

    # 3. Check process environment
    env_var = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if len(env_var) > 5:
        return env_var

    return ""

def mask_key(key):
    if len(key) <= 8:
        return "****"
    return f"{key[:8]}...{key[-4:]}"

def setup_env():
    env_path = os.path.join(APP_DIR, ".env")
    existing_key = find_existing_api_key()

    if existing_key:
        info(f"Existing OpenRouter API key found: {mask_key(existing_key)}")
        keep_choice = safe_input("Keep existing OpenRouter API key? (Y/n): ", "y")
        if keep_choice.lower() == "y":
            # Ensure persisted to .env if not already there
            if not os.path.exists(env_path):
                with open(env_path, "w", encoding="utf-8") as f:
                    f.write(f"OPENROUTER_API_KEY={existing_key}\nPORT={PORT}\n")
                os.chmod(env_path, 0o600)
                success(f"Preserved API key to {env_path}")
            return
        
        # User explicitly wants to change key
        print("\nEntering new OpenRouter API key (press Enter to cancel and keep current key):", file=sys.stderr)
        try:
            if sys.stdin.isatty():
                new_key = getpass.getpass("New OpenRouter API Key (sk-or-v1-...): ")
            else:
                new_key = safe_input("New OpenRouter API Key (sk-or-v1-...): ", "")
        except Exception:
            new_key = safe_input("New OpenRouter API Key (sk-or-v1-...): ", "")

        new_key = new_key.strip()
        if not new_key:
            info("No new key entered. Keeping existing API key.")
            return

        api_key = new_key
    else:
        # No existing key found anywhere
        warn("No OpenRouter API key found.")
        print("\033[1;36m[SETUP]\033[0m An OpenRouter API key is required for Claude Desktop Gateway mode.", file=sys.stderr)
        print("", file=sys.stderr)
        try:
            if sys.stdin.isatty():
                api_key = getpass.getpass("Enter your OpenRouter API Key (sk-or-v1-...): ")
            else:
                api_key = safe_input("Enter your OpenRouter API Key (sk-or-v1-...): ", "")
        except Exception:
            api_key = safe_input("Enter your OpenRouter API Key (sk-or-v1-...): ", "")

        api_key = api_key.strip()
        if not api_key:
            error("API key cannot be empty.")
            sys.exit(1)

    validate_openrouter_key(api_key)

    # Backup existing .env if present
    if os.path.exists(env_path):
        bak_path = f"{env_path}.bak.{int(datetime.now().timestamp())}"
        try:
            shutil.copy2(env_path, bak_path)
        except Exception:
            pass

    with open(env_path, "w", encoding="utf-8") as f:
        f.write(f"OPENROUTER_API_KEY={api_key}\nPORT={PORT}\n")
    os.chmod(env_path, 0o600)
    success(f"Environment file written to {env_path}")


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
                m_target_match = re.search(r"model:\s*openrouter/([^\s]+)", b)
                if m_target_match:
                    current_map[m_name] = m_target_match.group(1).strip()
        except Exception:
            pass
    return current_map

def fetch_openrouter_catalog():
    info("Fetching live model catalog & pricing from OpenRouter API...")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/models",
        headers={"User-Agent": "Claude-OpenRouter-Models/1.2.0"}
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
            "name": fallback_name,
            "price_str": item["price_str"],
            "ctx_str": item["ctx_str"],
            "supports1m": item["supports1m"],
            "is_recommended": is_recommended
        }
    return {
        "id": model_id,
        "name": fallback_name,
        "price_str": fallback_price,
        "ctx_str": fallback_ctx,
        "supports1m": fallback_1m,
        "is_recommended": is_recommended
    }

def run_model_configuration():
    check_claude_closed()
    setup_env(force=False)
    catalog = fetch_openrouter_catalog()
    current_config = read_current_config()

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
    print("Pricing displayed as ($In / $Out per 1M tokens) fetched from OpenRouter.\n", file=sys.stderr)

    selections = []

    for idx, t in enumerate(tiers, 1):
        print(f"\033[1;35m--- [{idx}/5] {t['tier_label']} ---\033[0m", file=sys.stderr)
        
        current_model_id = current_config.get(t["claude_name"])
        matched_current_idx = None
        recommended_idx = 1

        for opt_idx, opt in enumerate(t["options"], 1):
            is_current = (current_model_id is not None and opt["id"] == current_model_id)
            if is_current:
                matched_current_idx = opt_idx
            if opt.get("is_recommended"):
                recommended_idx = opt_idx

            tags = []
            if opt.get("is_recommended"):
                tags.append("\033[1;32m(Recommended)\033[0m")
            if is_current:
                tags.append("\033[1;33m[CURRENT]\033[0m")

            tag_str = f" {' '.join(tags)}" if tags else ""
            print(f"{opt_idx}) {opt['name']:<24} - {opt['price_str']:<14} [{opt['ctx_str']}]{tag_str}", file=sys.stderr)

        custom_num = len(t["options"]) + 1
        custom_tag = ""
        if matched_current_idx is None and current_model_id:
            custom_tag = f" \033[1;33m[CURRENT: {current_model_id}]\033[0m"
            matched_current_idx = custom_num

        print(f"{custom_num}) Custom OpenRouter Model ID{custom_tag}", file=sys.stderr)

        if matched_current_idx is not None:
            default_choice = str(matched_current_idx)
            if matched_current_idx == custom_num:
                default_hint = f"default={default_choice} (Current: {current_model_id})"
            else:
                default_hint = f"default={default_choice} (Current)"
        else:
            default_choice = str(recommended_idx)
            default_hint = f"default={default_choice} (Recommended)"

        user_choice = safe_input(f"Select {t['tier_name'].upper()} model [1-{custom_num}, {default_hint}]: ", default_choice)

        try:
            choice_num = int(user_choice)
        except ValueError:
            choice_num = int(default_choice)

        if 1 <= choice_num <= len(t["options"]):
            chosen = t["options"][choice_num - 1]
            model_id = chosen["id"]
            label = f"{chosen['name']} ({chosen['price_str']})"
            supports1m = chosen["supports1m"]
        else:
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


        selections.append({
            "tier": t["tier_name"],
            "claude_name": t["claude_name"],
            "model_id": model_id,
            "label": label,
            "supports1m": supports1m
        })
        print("", file=sys.stderr)

    # 1. Write LiteLLM config.yaml
    os.makedirs(APP_DIR, exist_ok=True)
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
        yaml_lines.append(f"      model: openrouter/{s['model_id']}")
        yaml_lines.append(f"      api_key: os.environ/OPENROUTER_API_KEY\n")
    yaml_lines.append("general_settings:")
    yaml_lines.append("  master_key: dummy-key\n")

    with open(config_yaml_path, "w", encoding="utf-8") as f:
        f.write("\n".join(yaml_lines))
    success(f"Generated LiteLLM config at: {config_yaml_path}")

    # 2. Write Claude 3P configLibrary JSON
    os.makedirs(CLAUDE_3P_DIR, exist_ok=True)
    meta_path = os.path.join(CLAUDE_3P_DIR, "_meta.json")
    applied_id = None
    if os.path.exists(meta_path):
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                meta = json.load(f)
                applied_id = meta.get("appliedId")
        except Exception:
            pass

    if not applied_id:
        applied_id = str(uuid.uuid4())
        meta = {
            "appliedId": applied_id,
            "entries": [{"id": applied_id, "name": "Default"}]
        }
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
    success(f"Synchronized Claude 3P config profile at: {profile_path}")

def create_runner_script():
    runner = os.path.join(APP_DIR, "run_proxy.sh")
    content = f"""#!/usr/bin/env bash
DIR="{APP_DIR}"
if [ -f "$DIR/.env" ]; then
    set -a
    source "$DIR/.env"
    set +a
fi
exec "$DIR/venv/bin/litellm" --config "$DIR/config.yaml" --port "${{PORT:-{PORT}}}" --host 127.0.0.1
"""
    with open(runner, "w", encoding="utf-8") as f:
        f.write(content)
    os.chmod(runner, 0o755)

def install_service():
    if platform.system() != "Darwin":
        info("Background service auto-start is only configured for macOS launchd.")
        return

    info(f"Creating macOS launchd service plist at {PLIST_PATH}...")
    plist_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{PLIST_LABEL}</string>
    <key>Version</key>
    <string>{VERSION}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>{APP_DIR}/run_proxy.sh</string>
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

    info("Loading service into launchd...")
    subprocess.run(["launchctl", "unload", PLIST_PATH], capture_output=True)
    subprocess.run(["launchctl", "load", PLIST_PATH], capture_output=True)

    success(f"Service installed and started as background daemon ({PLIST_LABEL} v{VERSION}).")
    print(f"Logs are available at: {APP_DIR}/logs/", file=sys.stderr)

def uninstall_service():
    info("Stopping and removing launchd service...")
    if os.path.exists(PLIST_PATH):
        subprocess.run(["launchctl", "unload", PLIST_PATH], capture_output=True)
        try:
            os.remove(PLIST_PATH)
        except Exception:
            pass
        success(f"Removed launchd plist: {PLIST_PATH}")

    for legacy in LEGACY_PLIST_LABELS:
        legacy_path = os.path.expanduser(f"~/Library/LaunchAgents/{legacy}.plist")
        if os.path.exists(legacy_path):
            subprocess.run(["launchctl", "unload", legacy_path], capture_output=True)
            try:
                os.remove(legacy_path)
            except Exception:
                pass

    clean_all = safe_input(f"Do you also want to remove all configuration, logs, and venv in {APP_DIR}? (y/N): ", "n")
    if clean_all.lower() == "y":
        shutil.rmtree(APP_DIR, ignore_errors=True)
        for legacy in LEGACY_APP_DIRS:
            if os.path.islink(legacy):
                try:
                    os.unlink(legacy)
                except Exception:
                    pass
        success(f"Removed {APP_DIR} and legacy links.")
    success("Uninstall complete.")

def status_service():
    header("Proxy & Claude 3P Status")
    info(f"Curated model recommendations last revisited: {MODELS_LAST_REVISITED}")
    
    if platform.system() == "Darwin":
        res = subprocess.run(["launchctl", "list", PLIST_LABEL], capture_output=True)
        if res.returncode == 0:
            success(f"Daemon {PLIST_LABEL} (v{VERSION}) is RUNNING.")
        else:
            warn(f"Daemon {PLIST_LABEL} is NOT running.")

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
        error(f"No OpenRouter API key configured in {env_path}!")
        print("\033[1;31m[CRITICAL]\033[0m Claude Desktop will fail with 401 'No cookie auth credentials found' until an API key is saved.", file=sys.stderr)
        print("Run \033[1;36m./setup.sh install\033[0m to enter and save your OpenRouter API key.", file=sys.stderr)

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
        info("Active Claude 3P Config Profile:")
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                print(json.dumps(json.load(f), indent=2), file=sys.stderr)
        except Exception:
            pass

def post_setup_prompt():
    print("", file=sys.stderr)
    if platform.system() == "Darwin":
        choice = safe_input("Would you like to launch Claude Desktop now? (Y/n): ", "y")
        if choice.lower() == "y":
            subprocess.run(["open", "-a", "Claude"], capture_output=True)
            success("Claude Desktop launched.")

def usage():
    print(f"Claude OpenRouter Models Setup v{VERSION}", file=sys.stderr)
    print("Usage: setup.sh {install|models|status|restart|stop|start|uninstall|version}\n", file=sys.stderr)
    print("Commands:", file=sys.stderr)
    print("  install    - Full setup: migrate dirs, venv, API key, live model selector, Claude 3P config & launchd daemon", file=sys.stderr)
    print("  models     - Live model selector only (updates LiteLLM YAML & Claude 3P config without reinstalling)", file=sys.stderr)
    print("  status     - Checks launchd daemon status, proxy connectivity, and Claude 3P profiles", file=sys.stderr)
    print("  start      - Starts the launchd daemon", file=sys.stderr)
    print("  stop       - Stops the launchd daemon", file=sys.stderr)
    print("  restart    - Restarts the launchd daemon", file=sys.stderr)
    print("  uninstall  - Unregisters and deletes the launchd startup daemon", file=sys.stderr)
    print("  version    - Displays the current proxy script version", file=sys.stderr)
    sys.exit(1)

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "install"

    if cmd == "install":
        migrate_legacy_dirs()
        setup_env()
        run_model_configuration()
        create_runner_script()
        install_service()
        status_service()
        post_setup_prompt()
    elif cmd == "models":
        migrate_legacy_dirs()
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
        migrate_legacy_dirs()
        create_runner_script()
        install_service()
        status_service()
    elif cmd == "start":
        subprocess.run(["launchctl", "load", PLIST_PATH], capture_output=True)
        success(f"Started {PLIST_LABEL}")
    elif cmd == "stop":
        subprocess.run(["launchctl", "unload", PLIST_PATH], capture_output=True)
        for legacy in LEGACY_PLIST_LABELS:
            legacy_path = os.path.expanduser(f"~/Library/LaunchAgents/{legacy}.plist")
            subprocess.run(["launchctl", "unload", legacy_path], capture_output=True)
        success("Stopped proxy daemon")
    elif cmd == "uninstall":
        uninstall_service()
    elif cmd in ("version", "--version", "-v"):
        print(f"Claude OpenRouter Models v{VERSION}")
    else:
        usage()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\033[1;33m[ABORTED]\033[0m Cancelled by user.", file=sys.stderr)
        sys.exit(130)