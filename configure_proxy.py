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

# Date when curated tier recommendations were last reviewed/updated
MODELS_LAST_REVISITED = "2026-08-21"

# Helper formatting
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
    except (EOFError, KeyboardInterrupt, Exception):
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
    app_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.claude-to-openrouter-proxy")
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
    main()
