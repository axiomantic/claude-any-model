#!/usr/bin/env bash
set -euo pipefail

# Script and Service Version
VERSION="1.2.0"
MODELS_LAST_REVISITED="2026-08-21"


# Configuration paths
APP_DIR="${HOME}/.claude-openrouter-models"
LEGACY_APP_DIRS=("${HOME}/.claude-to-openrouter-proxy" "${HOME}/.litellm-proxy")
PLIST_LABEL="com.claude-openrouter-models"
LEGACY_PLIST_LABELS=("com.claude-to-openrouter-proxy" "com.litellm.proxy")
PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"
PORT=3010

# Detect Script Directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

# Detect Claude 3P config directory by OS
detect_claude_3p_dir() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "${HOME}/Library/Application Support/Claude-3p/configLibrary"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "${HOME}/.config/Claude-3p/configLibrary"
    elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
        echo "${LOCALAPPDATA:-$HOME/AppData/Local}/Claude-3p/configLibrary"
    else
        echo "${HOME}/Library/Application Support/Claude-3p/configLibrary"
    fi
}

CLAUDE_3P_DIR="$(detect_claude_3p_dir)"


# Helper formatting
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
header() {
    echo -e "\n\033[1;36m============================================================\033[0m"
    echo -e "\033[1;36m  $* (v${VERSION})\033[0m"
    echo -e "\033[1;36m============================================================\033[0m"
}

# TTY-aware interactive prompt helper for curl | bash one-liners
prompt_read() {
    local prompt_msg="$1"
    local out_var="$2"
    local default_val="${3:-}"
    local is_secret="${4:-false}"
    local user_input=""

    if [ -t 0 ]; then
        if [ "$is_secret" = "true" ]; then
            read -rsp "$prompt_msg" user_input
            echo ""
        else
            read -rp "$prompt_msg" user_input
        fi
    elif [ -e /dev/tty ]; then
        if [ "$is_secret" = "true" ]; then
            read -rsp "$prompt_msg" user_input < /dev/tty
            echo ""
        else
            read -rp "$prompt_msg" user_input < /dev/tty
        fi
    else
        user_input="$default_val"
    fi

    printf -v "$out_var" "%s" "${user_input:-$default_val}"
}

# Migrate legacy directories and launchd services if present
migrate_legacy_dir() {
    shopt -s dotglob nullglob
    for legacy_dir in "${LEGACY_APP_DIRS[@]}"; do
        if [[ -d "${legacy_dir}" && ! -L "${legacy_dir}" ]]; then
            info "Migrating legacy proxy directory from ${legacy_dir} to ${APP_DIR}..."
            if [[ ! -d "${APP_DIR}" ]]; then
                mv "${legacy_dir}" "${APP_DIR}"
                ln -s "${APP_DIR}" "${legacy_dir}"
                success "Moved ${legacy_dir} -> ${APP_DIR} and created compatibility symlink."
            else
                cp -rn "${legacy_dir}/"* "${APP_DIR}/" 2>/dev/null || true
                rm -rf "${legacy_dir}"
                ln -s "${APP_DIR}" "${legacy_dir}"
                success "Merged ${legacy_dir} into ${APP_DIR} and created compatibility symlink."
            fi
        elif [[ ! -e "${legacy_dir}" && -d "${APP_DIR}" ]]; then
            ln -s "${APP_DIR}" "${legacy_dir}"
        fi
    done
    shopt -u dotglob nullglob


    # Unload and remove legacy launchd plists
    for legacy_label in "${LEGACY_PLIST_LABELS[@]}"; do
        local legacy_plist="${HOME}/Library/LaunchAgents/${legacy_label}.plist"
        if [[ -f "${legacy_plist}" ]]; then
            info "Unloading legacy launchd daemon (${legacy_label})..."
            launchctl unload "${legacy_plist}" 2>/dev/null || true
            rm -f "${legacy_plist}"
        fi
    done
}

ensure_dirs() {
    mkdir -p "${APP_DIR}"
    mkdir -p "${HOME}/Library/LaunchAgents"
    mkdir -p "${APP_DIR}/logs"
    mkdir -p "${CLAUDE_3P_DIR}"
    migrate_legacy_dir
}


# Check if Claude Desktop is running and block until user closes it
check_claude_closed() {
    local running=false
    while true; do
        if pgrep -i -x "Claude" >/dev/null 2>&1 || pgrep -i -f "Claude.app/Contents/MacOS" >/dev/null 2>&1; then
            running=true
            echo ""
            warn "Claude Desktop is currently RUNNING."
            echo -e "\033[1;33m[ACTION REQUIRED]\033[0m Please quit Claude Desktop (Cmd+Q) to safely apply third-party configuration."
            prompt_read "Press [Enter] once Claude Desktop has exited (or Ctrl+C to abort)..." _ ""
        else
            if [ "$running" = true ]; then
                success "Claude Desktop is closed. Proceeding..."
            fi
            break
        fi
    done
}

# Validate OpenRouter API key against OpenRouter API
validate_openrouter_key() {
    local key="$1"
    info "Validating OpenRouter API key..."
    local res
    res=$(curl -s -w "%{http_code}" -o /dev/null -H "Authorization: Bearer ${key}" "https://openrouter.ai/api/v1/auth/key" 2>/dev/null || echo "000")
    if [[ "$res" == "200" ]]; then
        success "OpenRouter API key verified successfully."
        return 0
    else
        warn "Could not verify OpenRouter key (HTTP $res). Proceeding anyway in case of offline/firewall restrictions."
        return 0
    fi
}

setup_env() {
    if [[ -f "${APP_DIR}/.env" ]]; then
        info "Existing .env file found at ${APP_DIR}/.env."
        local choice=""
        prompt_read "Do you want to overwrite your OpenRouter API key? (y/N): " choice "n"
        if [[ ! "$choice" =~ ^[Yy]$ ]]; then
            return
        fi
    fi

    echo ""
    local api_key=""
    prompt_read "Enter your OpenRouter API Key (sk-or-v1-...): " api_key "" "true"

    if [[ -z "${api_key}" ]]; then
        error "API key cannot be empty."
        exit 1
    fi

    validate_openrouter_key "${api_key}"

    cat <<EOF > "${APP_DIR}/.env"
OPENROUTER_API_KEY=${api_key}
PORT=${PORT}
EOF
    chmod 600 "${APP_DIR}/.env"
    success "Environment file written to ${APP_DIR}/.env"
}

setup_venv() {
    info "Setting up Python virtual environment in ${APP_DIR}/venv..."
    if ! command -v python3 &>/dev/null; then
        error "Python 3 is required but was not found in PATH."
        exit 1
    fi

    if [[ ! -d "${APP_DIR}/venv" ]]; then
        python3 -m venv "${APP_DIR}/venv"
    fi

    info "Installing dependencies inside virtual environment..."
    "${APP_DIR}/venv/bin/pip" install --quiet --upgrade pip
    "${APP_DIR}/venv/bin/pip" install --quiet 'fastapi<0.140'
    "${APP_DIR}/venv/bin/pip" install --quiet 'litellm[proxy]'
    success "LiteLLM installed successfully."
}

# Python-driven Interactive Model Selection & Configuration Sync
run_model_configuration() {
    # Ensure Claude is closed before modifying the JSON files
    check_claude_closed

    local helper_script="${APP_DIR}/configure_proxy.py"
    if [[ -n "${SCRIPT_DIR:-}" && -f "${SCRIPT_DIR}/configure_proxy.py" ]]; then
        cp "${SCRIPT_DIR}/configure_proxy.py" "${helper_script}"
    fi

    # If helper script doesn't exist (e.g. run via curl piped to bash), generate it inline
    if [[ ! -f "${helper_script}" ]]; then
        cat <<'PYEOF' > "${helper_script}"
#!/usr/bin/env python3
"""
Claude to OpenRouter Proxy - Interactive Tier & Model Configuration
Version: 1.2.0
"""
import sys
import os
import re
import json
import uuid
import urllib.request
from datetime import datetime

def info(msg): print(f"\033[1;34m[INFO]\033[0m {msg}", file=sys.stderr)
def success(msg): print(f"\033[1;32m[SUCCESS]\033[0m {msg}", file=sys.stderr)
def warn(msg): print(f"\033[1;33m[WARN]\033[0m {msg}", file=sys.stderr)
def header(msg):
    print(f"\n\033[1;36m============================================================\033[0m", file=sys.stderr)
    print(f"\033[1;36m  {msg}\033[0m", file=sys.stderr)
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


def read_current_config(app_dir):
    config_path = os.path.join(app_dir, "config.yaml")
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
        headers={"User-Agent": "Claude-Proxy-Setup/1.2.0"}
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

def main():
    app_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.claude-openrouter-models")
    claude_3p_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/Library/Application Support/Claude-3p/configLibrary")
    port = sys.argv[3] if len(sys.argv) > 3 else "3010"


    catalog = fetch_openrouter_catalog()
    current_config = read_current_config(app_dir)

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

    header("Configure Inference Models for Claude Desktop")
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
        print(f"{custom_num}) Custom OpenRouter Model ID", file=sys.stderr)

        # Default to current selection if set, otherwise default to recommended
        if matched_current_idx is not None:
            default_choice = str(matched_current_idx)
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
            custom_id = safe_input("Enter OpenRouter model ID (e.g. org/model-name): ", t["options"][0]["id"])
            item = catalog.get(custom_id)
            if item:
                print(f"\033[1;32m[API Match]\033[0m Found {item['name']}: {item['price_str']} [{item['ctx_str']}]", file=sys.stderr)
                model_id = custom_id
                label = f"{item['name']} ({item['price_str']})"
                supports1m = item["supports1m"]
            else:
                custom_label = safe_input("Enter display label with price (e.g. MyModel ($1.00/$2.00)): ", custom_id)
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
    os.makedirs(app_dir, exist_ok=True)
    config_yaml_path = os.path.join(app_dir, "config.yaml")
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
    os.makedirs(claude_3p_dir, exist_ok=True)
    meta_path = os.path.join(claude_3p_dir, "_meta.json")
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

    profile_path = os.path.join(claude_3p_dir, f"{applied_id}.json")
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
        "inferenceGatewayBaseUrl": f"http://127.0.0.1:{port}",
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

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\033[1;33m[ABORTED]\033[0m Configuration cancelled by user.", file=sys.stderr)
        sys.exit(130)
PYEOF
        chmod +x "${helper_script}"
    fi

    # Execute Python configuration with TTY stdin redirection if available
    if [ ! -t 0 ] && [ -e /dev/tty ]; then
        python3 "${helper_script}" "${APP_DIR}" "${CLAUDE_3P_DIR}" "${PORT}" < /dev/tty || exit $?
    else
        python3 "${helper_script}" "${APP_DIR}" "${CLAUDE_3P_DIR}" "${PORT}" || exit $?
    fi
}




create_runner_script() {
    local runner="${APP_DIR}/run_proxy.sh"
    cat <<'EOF' > "${runner}"
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$DIR/.env" ]; then
    set -a
    source "$DIR/.env"
    set +a
fi
exec "$DIR/venv/bin/litellm" --config "$DIR/config.yaml" --port "${PORT:-3010}" --host 127.0.0.1
EOF
    chmod +x "${runner}"
}

install_service() {
    info "Creating macOS launchd service plist at ${PLIST_PATH}..."
    cat <<EOF > "${PLIST_PATH}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>Version</key>
    <string>${VERSION}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${APP_DIR}/run_proxy.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${APP_DIR}/logs/litellm.out.log</string>
    <key>StandardErrorPath</key>
    <string>${APP_DIR}/logs/litellm.err.log</string>
    <key>WorkingDirectory</key>
    <string>${APP_DIR}</string>
</dict>
</plist>
EOF

    info "Loading service into launchd..."
    launchctl unload "${PLIST_PATH}" 2>/dev/null || true
    launchctl load "${PLIST_PATH}"

    success "Service installed and started as a background daemon (${PLIST_LABEL} v${VERSION})."
    echo "Logs are available at: ${APP_DIR}/logs/"
}

uninstall_service() {
    info "Stopping and removing launchd service..."
    if [[ -f "${PLIST_PATH}" ]]; then
        launchctl unload "${PLIST_PATH}" 2>/dev/null || true
        rm -f "${PLIST_PATH}"
        success "Removed launchd plist: ${PLIST_PATH}"
    fi
    for legacy_label in "${LEGACY_PLIST_LABELS[@]}"; do
        local legacy_plist="${HOME}/Library/LaunchAgents/${legacy_label}.plist"
        if [[ -f "${legacy_plist}" ]]; then
            launchctl unload "${legacy_plist}" 2>/dev/null || true
            rm -f "${legacy_plist}"
        fi
    done

    local clean_all=""
    prompt_read "Do you also want to remove all configuration, logs, and venv in ${APP_DIR}? (y/N): " clean_all "n"
    if [[ "$clean_all" =~ ^[Yy]$ ]]; then
        rm -rf "${APP_DIR}" "${LEGACY_APP_DIRS[@]}"
        success "Removed ${APP_DIR} and legacy links"
    fi
    success "Uninstall complete."
}

status_service() {
    header "Proxy & Claude 3P Status"
    info "Curated model recommendations last revisited: ${MODELS_LAST_REVISITED}"
    if launchctl list | grep -q "${PLIST_LABEL}"; then
        success "Daemon ${PLIST_LABEL} (v${VERSION}) is RUNNING."
    else
        local found_legacy=false
        for legacy_label in "${LEGACY_PLIST_LABELS[@]}"; do
            if launchctl list | grep -q "${legacy_label}"; then
                warn "Legacy daemon ${legacy_label} is running. Run './setup.sh restart' to migrate."
                found_legacy=true
                break
            fi
        done
        if [ "$found_legacy" = false ]; then
            warn "Daemon ${PLIST_LABEL} is NOT running."
        fi
    fi

    echo ""
    info "Testing endpoint connectivity on port ${PORT}..."
    local max_attempts=6
    local attempt=1
    local success=false

    while [ $attempt -le $max_attempts ]; do
        local code
        code=$(curl -s -w "%{http_code}" -o /dev/null "http://127.0.0.1:${PORT}/health/liveliness" 2>/dev/null || echo "000")
        if [[ "$code" == "200" ]] || curl -s "http://127.0.0.1:${PORT}/health/liveliness" 2>/dev/null | grep -q "alive"; then
            success=true
            break
        fi
        info "Waiting for proxy to respond (attempt $attempt/$max_attempts)..."
        sleep 2
        ((attempt++))
    done

    if [ "$success" = true ]; then
        success "Proxy is active and healthy on http://127.0.0.1:${PORT}"
    else
        warn "Could not verify liveliness on http://127.0.0.1:${PORT}. Check logs at ${APP_DIR}/logs/litellm.err.log"
    fi

    echo ""
    if [[ -f "${CLAUDE_3P_DIR}/_meta.json" ]]; then
        info "Active Claude 3P Config Profile:"
        cat "${CLAUDE_3P_DIR}/_meta.json"
    fi
}

post_setup_prompt() {
    echo ""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local launch_choice=""
        prompt_read "Would you like to launch Claude Desktop now? (Y/n): " launch_choice "y"
        if [[ "$launch_choice" =~ ^[Yy]$ ]]; then
            open -a Claude 2>/dev/null || open -a "Claude Desktop" 2>/dev/null || warn "Could not find Claude in Applications."
            success "Claude Desktop launched."
        fi
    fi
}

usage() {
    echo "Claude OpenRouter Models Setup v${VERSION}"
    echo "Usage: $0 {install|models|status|restart|stop|start|uninstall|version}"
    echo ""
    echo "Commands:"
    echo "  install    - Full setup: migrate dirs, venv, API key, live model selector, Claude 3P config & launchd daemon"
    echo "  models     - Live model selector only (updates LiteLLM YAML & Claude 3P config without reinstalling)"
    echo "  status     - Checks launchd daemon status, proxy connectivity, and Claude 3P profiles"
    echo "  start      - Starts the launchd daemon"
    echo "  stop       - Stops the launchd daemon"
    echo "  restart    - Restarts the launchd daemon (and migrates legacy service if needed)"
    echo "  uninstall  - Unregisters and deletes the launchd startup daemon"
    echo "  version    - Displays the current proxy script version"
    exit 1
}

# Command dispatch
case "${1:-install}" in
    install)
        ensure_dirs
        setup_env
        setup_venv
        run_model_configuration
        create_runner_script
        install_service
        status_service
        post_setup_prompt
        ;;
    models)
        ensure_dirs
        run_model_configuration
        local restart_needed=false
        if launchctl list | grep -q "${PLIST_LABEL}"; then
            restart_needed=true
        else
            for legacy_label in "${LEGACY_PLIST_LABELS[@]}"; do
                if launchctl list | grep -q "${legacy_label}"; then
                    restart_needed=true
                    break
                fi
            done
        fi
        if [ "$restart_needed" = true ]; then
            info "Restarting proxy to apply new YAML configuration..."
            for legacy_label in "${LEGACY_PLIST_LABELS[@]}"; do
                launchctl unload "${HOME}/Library/LaunchAgents/${legacy_label}.plist" 2>/dev/null || true
                rm -f "${HOME}/Library/LaunchAgents/${legacy_label}.plist"
            done
            launchctl unload "${PLIST_PATH}" 2>/dev/null || true
            install_service
            success "Proxy restarted with updated configuration."
        fi
        status_service
        post_setup_prompt
        ;;
    uninstall)
        uninstall_service
        ;;
    status)
        status_service
        ;;
    start)
        launchctl load "${PLIST_PATH}"
        success "Started ${PLIST_LABEL}"
        ;;
    stop)
        launchctl unload "${PLIST_PATH}" 2>/dev/null || true
        for legacy_label in "${LEGACY_PLIST_LABELS[@]}"; do
            launchctl unload "${HOME}/Library/LaunchAgents/${legacy_label}.plist" 2>/dev/null || true
        done
        success "Stopped proxy daemon"
        ;;
    restart)
        ensure_dirs
        create_runner_script
        install_service
        status_service
        ;;
    version|--version|-v)
        echo "Claude OpenRouter Models v${VERSION}"
        ;;
    *)
        usage
        ;;
esac