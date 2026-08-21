#!/usr/bin/env python3
"""
Semantic Model Recommender & Evaluator (LLM + Web Search Grounding)
Queries OpenRouter models with online web search plugin to analyze the latest
state of AI models, benchmark rankings, and pricing compared to Anthropic tiers.
"""

import os
import sys
import json
import re
import urllib.request
from datetime import datetime, timezone

OPENROUTER_MODELS_URL = "https://openrouter.ai/api/v1/models"
OPENROUTER_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"

# Default reasoning model with web search grounding
DEFAULT_REASONING_MODEL = "google/gemini-2.0-flash-001"

def info(msg): print(f"\033[1;34m[INFO]\033[0m {msg}", file=sys.stderr)
def success(msg): print(f"\033[1;32m[SUCCESS]\033[0m {msg}", file=sys.stderr)
def warn(msg): print(f"\033[1;33m[WARN]\033[0m {msg}", file=sys.stderr)
def error(msg): print(f"\033[1;31m[ERROR]\033[0m {msg}", file=sys.stderr)

def get_api_key():
    # Check env var
    key = os.environ.get("OPENROUTER_API_KEY")
    if key:
        return key.strip()
    
    # Check local .env file
    env_path = os.path.expanduser("~/.claude-openrouter-models/.env")
    if os.path.exists(env_path):
        try:
            with open(env_path, "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("OPENROUTER_API_KEY="):
                        return line.split("=", 1)[1].strip()
        except Exception:
            pass
    return None

def fetch_openrouter_catalog():
    info("Fetching full model catalog from OpenRouter API...")
    req = urllib.request.Request(
        OPENROUTER_MODELS_URL,
        headers={"User-Agent": "Claude-OpenRouter-Recommender/1.2.0"}
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode()).get("data", [])
            success(f"Retrieved {len(data)} total models from OpenRouter.")
            return data
    except Exception as e:
        error(f"Failed to fetch OpenRouter catalog: {e}")
        return []

def build_compact_catalog(models):
    catalog_map = {}
    compact_list = []
    for m in models:
        mid = m.get("id", "")
        p_in = float(m.get("pricing", {}).get("prompt", 0)) * 1_000_000
        p_out = float(m.get("pricing", {}).get("completion", 0)) * 1_000_000
        ctx = int(m.get("context_length", 0))
        name = m.get("name", mid)
        desc = m.get("description", "")[:160]

        # Ignore 0-pricing anomalous test models
        if p_in == 0 and p_out == 0 and "free" not in mid:
            continue

        entry = {
            "id": mid,
            "name": name,
            "p_in": p_in,
            "p_out": p_out,
            "price_str": f"${p_in:.2f}/${p_out:.2f}",
            "ctx": ctx,
            "ctx_str": f"{ctx // 1_000_000}M Context" if ctx >= 1_000_000 else f"{ctx // 1_000}k Context",
            "supports1m": ctx >= 900_000,
            "desc": desc
        }
        catalog_map[mid] = entry
        compact_list.append({
            "id": mid,
            "name": name,
            "price_in_1m": round(p_in, 2),
            "price_out_1m": round(p_out, 2),
            "context_k": ctx // 1000,
            "desc": desc
        })
    return catalog_map, compact_list

def perform_llm_semantic_analysis(api_key, compact_catalog, today_str):
    info("Querying LLM agent with online web search plugin via OpenRouter...")

    model_name = os.environ.get("REASONING_MODEL", DEFAULT_REASONING_MODEL)

    system_prompt = f"""You are an expert AI infrastructure architect and benchmark evaluator evaluating LLM price-performance as of {today_str}.
Your task is to analyze the current state of OpenRouter models and recommend the best alternatives for Anthropic's Claude family tiers.

Anthropic Family Tiers:
1. Opus Tier (Target alias: claude-opus-4):
   - Role: Heavyweight reasoning, mathematics, deep system architecture, frontier coding.
   - Anthropic reference: Claude 3.7 / 4 Opus ($15/$75 per 1M tokens).
   - Goal: Find state-of-the-art reasoning models with large context (prefer 1M) at 80-95% lower cost.

2. Sonnet Tier (Target alias: claude-sonnet-4-5):
   - Role: Fast, agentic daily workhorse, coding specialist, tool calling.
   - Anthropic reference: Claude 3.5 / 3.7 Sonnet ($3/$15 per 1M tokens).
   - Goal: Find ultra-fast, high SWE-bench / LiveBench coding models (e.g. Qwen Coder, DeepSeek, Sonnet variants).

3. Haiku Tier (Target alias: claude-3-haiku-20240307):
   - Role: Maximum throughput, low latency, budget operations.
   - Anthropic reference: Claude 3.5 Haiku ($0.80/$4.00 per 1M tokens).
   - Goal: Find sub-$0.30/M ultra-fast models (Flash, Nano, Mini, Luna).

4. Fable Tier (Target alias: claude-fable-5):
   - Role: Ultra-heavyweight multi-step agent runtime for large orchestration loops.
   - Goal: High context MoE/dense models with strong instruction following.

5. Mythos Tier (Target alias: claude-mythos-1):
   - Role: Frontier & experimental reasoning flagships.

Instructions:
- Use web search to review latest Arena Elo, LiveBench, SWE-bench Verified, and Chatbot Arena scores.
- Select 4-5 model IDs from the provided OpenRouter catalog for EACH tier.
- For each tier, pick 1 model as 'is_recommended': true.
- Provide a clear rationale explaining why each tier's models and recommendations were selected.
- Output MUST be valid JSON only.

JSON Format:
{{
  "executive_summary": "Summary of current model landscape, new releases, and cost comparison...",
  "web_search_findings": [
    "Finding 1 with recent benchmark or company release...",
    "Finding 2..."
  ],
  "tiers": [
    {{
      "tier_name": "opus",
      "tier_label": "OPUS TIER (Heavyweight Reasoning & Complex Architecture)",
      "claude_name": "claude-opus-4",
      "rationale": "Why these models were chosen for Opus tier...",
      "options": [
        {{
          "id": "exact_openrouter_model_id",
          "name": "Clean Display Name",
          "is_recommended": true,
          "rationale": "Reasoning for recommendation"
        }}
      ]
    }}
  ]
}}
"""

    user_prompt = f"""Current Date: {today_str}
Catalog Sample (Top Available OpenRouter Models):
{json.dumps(compact_catalog[:200], indent=1)}

Please perform web search on recent AI model releases and benchmarks, analyze the catalog, and return the structured JSON tier recommendations."""

    payload = {
        "model": model_name,
        "plugins": [{"id": "web"}],
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ],
        "temperature": 0.2
    }

    req = urllib.request.Request(
        OPENROUTER_CHAT_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://github.com/axiomantic/claude-openrouter-models",
            "X-Title": "Claude OpenRouter Models Recommender"
        }
    )

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode())
            content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
            
            # Extract JSON block
            json_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", content, re.DOTALL)
            if json_match:
                raw_json = json_match.group(1)
            else:
                raw_json = content.strip()
            
            parsed = json.loads(raw_json)
            success("Successfully received and parsed LLM semantic recommendations.")
            return parsed
    except Exception as e:
        error(f"LLM evaluation request failed: {e}")
        return None

def generate_markdown_report(analysis_result, catalog_map, today_str):
    lines = [
        f"# 🤖 OpenRouter Semantic Model Landscape & Tier Recommendations",
        f"**Generated on:** {today_str} UTC  ",
        f"**Evaluated by:** LLM Agent with Live Web Search Grounding  ",
        f"**Source:** [OpenRouter Model Catalog](https://openrouter.ai/models)\n",
        "---",
        "## 📑 Executive Summary\n",
        analysis_result.get("executive_summary", "Semantic evaluation completed."),
        "\n### 🌐 Web Search Findings & Market Observations\n"
    ]

    for finding in analysis_result.get("web_search_findings", []):
        lines.append(f"- {finding}")
    lines.append("")

    lines.append("---")
    lines.append("## 🎯 Recommended Tier Configurations\n")

    for t in analysis_result.get("tiers", []):
        tier_label = t.get("tier_label", t.get("tier_name", "").upper())
        claude_name = t.get("claude_name", "")
        rationale = t.get("rationale", "")

        lines.append(f"### 🏷️ {tier_label} (`{claude_name}`)")
        if rationale:
            lines.append(f"*{rationale}*\n")

        lines.append("| Model ID | Display Name | Live Price ($In / $Out) | Context | Status | Rationale |")
        lines.append("| :--- | :--- | :--- | :--- | :--- | :--- |")

        for opt in t.get("options", []):
            mid = opt.get("id", "")
            name = opt.get("name", mid)
            is_rec = opt.get("is_recommended", False)
            opt_rat = opt.get("rationale", "")

            cat_item = catalog_map.get(mid)
            if cat_item:
                price_str = cat_item["price_str"]
                ctx_str = cat_item["ctx_str"]
            else:
                price_str = "Live API"
                ctx_str = "1M Context"

            rec_badge = "**⭐ Recommended**" if is_rec else "Alternative"
            lines.append(f"| `{mid}` | {name} | **{price_str}** | {ctx_str} | {rec_badge} | {opt_rat} |")
        lines.append("")

    return "\n".join(lines)

def apply_recommendations_to_setup_sh(analysis_result, catalog_map, today_str):
    setup_path = "setup.sh"
    if not os.path.exists(setup_path):
        warn(f"{setup_path} not found.")
        return

    info(f"Applying semantic tier recommendations to {setup_path}...")
    with open(setup_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Build python tiers array string
    tier_blocks = []
    for t in analysis_result.get("tiers", []):
        opts_code = []
        for opt in t.get("options", []):
            mid = opt.get("id", "")
            name = opt.get("name", mid)
            is_rec = "True" if opt.get("is_recommended", False) else "False"
            
            cat_item = catalog_map.get(mid)
            if cat_item:
                p_str = cat_item["price_str"]
                c_str = cat_item["ctx_str"]
                supp1m = "True" if cat_item["supports1m"] else "False"
            else:
                p_str = "$1.00/$3.00"
                c_str = "1M Context"
                supp1m = "True"

            if is_rec == "True":
                opts_code.append(f'                get_model_entry(catalog, "{mid}", "{name}", "{p_str}", "{c_str}", {supp1m}, is_recommended=True),')
            else:
                opts_code.append(f'                get_model_entry(catalog, "{mid}", "{name}", "{p_str}", "{c_str}", {supp1m}),')

        opts_str = "\n".join(opts_code)
        block = f"""        {{
            "tier_name": "{t.get('tier_name')}",
            "tier_label": "{t.get('tier_label')}",
            "claude_name": "{t.get('claude_name')}",
            "options": [
{opts_str}
            ]
        }}"""
        tier_blocks.append(block)

    all_tiers_code = "    tiers = [\n" + ",\n".join(tier_blocks) + "\n    ]"

    # Replace tiers = [...] in setup.sh
    updated = re.sub(
        r"    tiers = \[\n.*?    \]",
        all_tiers_code,
        content,
        flags=re.DOTALL
    )

    # Update revisit timestamp
    updated = re.sub(
        r'^MODELS_LAST_REVISITED="[^"]+"',
        f'MODELS_LAST_REVISITED="{today_str}"',
        updated,
        flags=re.MULTILINE
    )
    updated = re.sub(
        r'^MODELS_LAST_REVISITED = "[^"]+"',
        f'MODELS_LAST_REVISITED = "{today_str}"',
        updated,
        flags=re.MULTILINE
    )

    with open(setup_path, "w", encoding="utf-8") as f:
        f.write(updated)
    success(f"Successfully updated tier definitions and timestamp ({today_str}) in {setup_path}.")

def main():
    apply_mode = "--apply" in sys.argv
    today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    api_key = get_api_key()
    if not api_key:
        warn("No OPENROUTER_API_KEY found. Live LLM semantic analysis with web search requires an API key.")
        print("Please set OPENROUTER_API_KEY environment variable or configure ~/.claude-openrouter-models/.env", file=sys.stderr)
        sys.exit(1)

    catalog = fetch_openrouter_catalog()
    if not catalog:
        sys.exit(1)

    catalog_map, compact_catalog = build_compact_catalog(catalog)

    analysis_result = perform_llm_semantic_analysis(api_key, compact_catalog, today_str)
    if not analysis_result:
        error("Could not obtain valid semantic analysis from LLM.")
        sys.exit(1)

    report_md = generate_markdown_report(analysis_result, catalog_map, today_str)
    report_file = "MODEL_RECOMMENDATIONS_REPORT.md"
    with open(report_file, "w", encoding="utf-8") as f:
        f.write(report_md)
    success(f"Wrote full semantic evaluation report to {report_file}")

    if apply_mode:
        apply_recommendations_to_setup_sh(analysis_result, catalog_map, today_str)

if __name__ == "__main__":
    main()
