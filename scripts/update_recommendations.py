#!/usr/bin/env python3
"""
Semantic Model Recommender & Comparative Delta Evaluator (LLM + Web Search Grounding)
Queries OpenRouter models with online web search grounding to analyze the latest
state of AI models, benchmark rankings, and pricing compared to Anthropic tiers,
and performs a comprehensive BEFORE vs AFTER delta diff against the active claude-threepio script.
"""

import os
import sys
import json
import re
import urllib.request
from datetime import datetime, timezone

OPENROUTER_MODELS_URL = "https://openrouter.ai/api/v1/models"
OPENROUTER_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"

def info(msg): print(f"\033[1;34m[INFO]\033[0m {msg}", file=sys.stderr)
def success(msg): print(f"\033[1;32m[SUCCESS]\033[0m {msg}", file=sys.stderr)
def warn(msg): print(f"\033[1;33m[WARN]\033[0m {msg}", file=sys.stderr)
def error(msg): print(f"\033[1;31m[ERROR]\033[0m {msg}", file=sys.stderr)

def get_api_key():
    key = os.environ.get("OPENROUTER_API_KEY")
    if key:
        return key.strip()
    
    env_path = os.path.expanduser("~/.claude-threepio/.env")
    if os.path.exists(env_path):
        try:
            with open(env_path, "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("OPENROUTER_API_KEY="):
                        return line.split("=", 1)[1].strip()
        except Exception:
            pass
    return None

def extract_current_tiers(setup_path="claude-threepio"):
    if not os.path.exists(setup_path):
        return []
    with open(setup_path, "r", encoding="utf-8") as f:
        content = f.read()
    
    tiers = []
    tier_matches = re.finditer(
        r'\{\s*"tier_name":\s*"([^"]+)",\s*"tier_label":\s*"([^"]+)",\s*"claude_name":\s*"([^"]+)",\s*"options":\s*\[(.*?)\](?:,\s*"ollama_options":\s*(ollama_opts\(\[.*?\]\)))?,?\s*\}',
        content,
        re.DOTALL
    )
    for m in tier_matches:
        tname, tlabel, cname, opt_text, ollama_block = m.groups()
        opts = []
        for line in opt_text.strip().split("\n"):
            om = re.search(r'get_model_entry\(catalog,\s*"([^"]+)",\s*"([^"]+)",\s*"([^"]+)",\s*"([^"]+)",\s*(True|False)(?:,\s*is_recommended=(True|False))?\)', line)
            if om:
                opts.append({
                    "id": om.group(1),
                    "name": om.group(2),
                    "price_str": om.group(3),
                    "ctx_str": om.group(4),
                    "supports1m": om.group(5) == "True",
                    "is_recommended": om.group(6) == "True" if om.group(6) else False
                })
        tiers.append({
            "tier_name": tname,
            "tier_label": tlabel,
            "claude_name": cname,
            "options": opts,
            "ollama_block": ollama_block
        })
    return tiers


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

def perform_llm_comparative_analysis(api_key, current_tiers, catalog_map, compact_catalog, today_str):
    info("Querying LLM agent with online web search plugin for comparative delta evaluation...")

    preferred_candidates = [
        "perplexity/sonar-pro-search",
        "perplexity/sonar",
        "openai/gpt-5-mini",
        "openai/gpt-4o-mini",
        "google/gemini-3.7-flash",
        "google/gemini-3.5-flash",
        "anthropic/claude-3.5-haiku",
        "deepseek/deepseek-chat"
    ]

    custom_model = os.environ.get("REASONING_MODEL")
    if custom_model:
        models_to_try = [custom_model]
    else:
        models_to_try = [m for m in preferred_candidates if m in catalog_map]
        if not models_to_try:
            models_to_try = preferred_candidates

    system_prompt = f"""You are an elite AI systems and LLM infrastructure architect conducting a scheduled comparative evaluation of inference models on OpenRouter for integration into the 'claude-threepio' proxy.

You are provided with:
1. THE CURRENTLY ACTIVE TIER CONFIGURATION from claude-threepio (what users currently see and use).
2. THE LIVE OPENROUTER MODEL CATALOG (with current token pricing and context lengths).

Your mission is NOT just to list models, but to conduct an actionable, comparative engineering audit comparing what is CURRENTLY configured in claude-threepio against the newest state of the art available on OpenRouter.

Anthropic Target Aliases:
- Opus Tier (claude-opus-4): Heavyweight reasoning, math, complex system architecture. Reference: Claude 3.7 / 4 Opus ($15/$75).
- Sonnet Tier (claude-sonnet-4-5): Fast agentic coding workhorse, tool calling, SWE-bench leader. Reference: Claude 3.5 / 3.7 Sonnet ($3/$15).
- Haiku Tier (claude-3-haiku-20240307): Maximum economy, high throughput, subagent routing (<$0.30/M).
- Fable Tier (claude-fable-5): Ultra-heavyweight multi-step agent runtime loops.
- Mythos Tier (claude-mythos-1): Frontier & experimental flagships.

Instructions:
1. Use online web search to research recent benchmark rankings (LiveBench, SWE-bench Verified, Arena Elo, Chatbot Arena, Artificial Analysis) and recent major releases (OpenAI, Anthropic, DeepSeek, Moonshot/Kimi, Zhipu/GLM, Qwen/Alibaba, Google, Meta, NVIDIA, Poolside, etc.).
2. PRICE DIVERSITY & TIER SPECTRUM REQUIREMENT:
   For EACH tier, curate a balanced spectrum across the curated options:
   - Free / Zero-Cost Option: Top $0.00 models from OpenRouter's free collection (e.g. models with :free or $0.00 pricing such as Nemotron 3 Ultra 550B, Ox Alpha, North Mini Code, Laguna S, Inkling Small, etc.).
   - Budget / High-Economy Option: Ultra-low token price (e.g. sub-$0.10/M for Haiku/Sonnet, sub-$1.50/M MoE for Opus/Fable).
   - Value Workhorse (Default/Recommended): Optimal benchmark score per dollar.
   - High-Throughput / Specialist: Fast, reliable tool calling, SWE-bench coding leader.
   - Frontier Ceiling Option: Highest capability ceiling for users prioritizing maximum reasoning.
3. For EACH tier, compare the CURRENT lineup in claude-threepio vs your PROPOSED updated lineup:
   - Identify which models are RETAINED, which models are REPLACED/SWAPPED OUT, and which new models are ADDED.
   - For every swap/change, provide the specific price delta ($In/$Out difference and % change) and benchmark/architectural justification.
   - Designate 1 model per tier as 'is_recommended': true. If the recommended model is different from the current one, explain why.
4. Provide an executive summary with cost savings and performance tradeoff matrix.
5. Output MUST be strictly valid JSON conforming to the schema below.


JSON Format Schema:
{{
  "executive_summary": "High-level summary of industry shifts, newly released models, and benchmark progress...",
  "web_search_grounding": [
    "Grounding point 1 with benchmark citations (LiveBench, SWE-bench, Arena Elo)...",
    "Grounding point 2..."
  ],
  "tier_comparisons": [
    {{
      "tier_name": "opus",
      "tier_label": "OPUS TIER (Heavyweight Reasoning & Complex Architecture)",
      "claude_name": "claude-opus-4",
      "current_recommended": "Current Recommended Model Name & ID",
      "proposed_recommended": "Proposed Recommended Model Name & ID",
      "recommended_change_summary": "Why the primary recommendation shifted or was maintained...",
      "delta_analysis": "In-depth analysis of capability changes, pricing differences, and benchmark comparisons for this tier...",
      "swaps_and_changes": [
        {{
          "action": "SWAP" or "RETAIN" or "ADD",
          "current_model": "Old Model Name (or None if new)",
          "proposed_model": "New Model Name & ID",
          "price_comparison": "$X.XX/$Y.YY vs $A.AA/$B.BB (Z% delta)",
          "benchmark_justification": "Why this change is superior..."
        }}
      ],
      "options": [
        {{
          "id": "exact_openrouter_model_id",
          "name": "Clean Display Name",
          "is_recommended": true,
          "rationale": "Why included in curated options"
        }}
      ]
    }}
  ]
}}
"""

    user_prompt = f"""Current Date: {today_str}

CURRENT ACTIVE CLAUDE-THREEPIO CONFIGURATION:
{json.dumps(current_tiers, indent=2)}

AVAILABLE LIVE OPENROUTER CATALOG:
{json.dumps(compact_catalog[:220], indent=1)}

Please perform web search on recent benchmarks and releases, conduct the comparative delta analysis against the active configuration, and return the structured JSON."""

    for model_name in models_to_try:
        info(f"Attempting comparative evaluation with model: {model_name}...")
        plugins = [{"id": "web"}] if not model_name.startswith("perplexity/") else []
        payload = {
            "model": model_name,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            "temperature": 0.2
        }
        if plugins:
            payload["plugins"] = plugins

        req = urllib.request.Request(
            OPENROUTER_CHAT_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
                "HTTP-Referer": "https://github.com/axiomantic/claude-threepio",
                "X-Title": "claude-threepio Comparative Evaluator"
            }
        )

        try:
            with urllib.request.urlopen(req, timeout=95) as resp:
                data = json.loads(resp.read().decode())
                content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
                
                json_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", content, re.DOTALL)
                if json_match:
                    raw_json = json_match.group(1)
                else:
                    raw_json = content.strip()
                
                parsed = json.loads(raw_json)
                success(f"Successfully received comparative recommendations using {model_name}.")
                return parsed
        except urllib.error.HTTPError as he:
            err_body = he.read().decode("utf-8", errors="ignore")
            warn(f"Model {model_name} HTTP Error {he.code}: {err_body}")
        except Exception as e:
            warn(f"Model {model_name} failed: {e}")

    error("All candidate models failed to return a valid comparative evaluation.")
    return None

def generate_comparative_markdown_report(analysis_result, current_tiers, catalog_map, today_str):
    curr_map = {t["tier_name"]: t for t in current_tiers}

    lines = [
        f"# 🤖 Weekly Model Recommendations & Comparative Delta Analysis",
        f"**Generated on:** {today_str} UTC  ",
        f"**Evaluation Engine:** LLM Agent with Live Web Search Grounding  ",
        f"**Source Data:** Live [OpenRouter Model Catalog](https://openrouter.ai/models)\n",
        "---",
        "## 📑 Executive Summary\n",
        analysis_result.get("executive_summary", "Comparative evaluation completed."),
        "\n### 🌐 Web Search Findings & Benchmark Grounding\n"
    ]

    for g in analysis_result.get("web_search_grounding", []):
        lines.append(f"- {g}")
    lines.append("")

    lines.append("---")
    lines.append("## 📊 Tier-by-Tier Comparative Delta Analysis\n")

    for tc in analysis_result.get("tier_comparisons", []):
        tname = tc.get("tier_name", "")
        tlabel = tc.get("tier_label", tname.upper())
        cname = tc.get("claude_name", "")
        curr_rec = tc.get("current_recommended", "N/A")
        prop_rec = tc.get("proposed_recommended", "N/A")
        rec_sum = tc.get("recommended_change_summary", "")
        delta_analysis = tc.get("delta_analysis", "")

        lines.append(f"### 🏷️ {tlabel} (`{cname}`)")
        lines.append(f"- **Current Recommended (in `claude-threepio`):** `{curr_rec}`")
        lines.append(f"- **Proposed Recommended:** **`{prop_rec}`**")
        if rec_sum:
            lines.append(f"- **Recommendation Shift Rationale:** {rec_sum}\n")
        if delta_analysis:
            lines.append(f"*{delta_analysis}*\n")

        # Swaps table
        swaps = tc.get("swaps_and_changes", [])
        if swaps:
            lines.append("#### 🔄 Model Swaps & Lineup Adjustments")
            lines.append("| Action | Previous Model | Proposed Model | Price Delta | Benchmark & Engineering Justification |")
            lines.append("| :--- | :--- | :--- | :--- | :--- |")
            for s in swaps:
                action = s.get("action", "SWAP")
                c_mod = s.get("current_model", "-")
                p_mod = s.get("proposed_model", "-")
                p_cmp = s.get("price_comparison", "-")
                b_just = s.get("benchmark_justification", "-")
                lines.append(f"| **{action}** | {c_mod} | `{p_mod}` | {p_cmp} | {b_just} |")
            lines.append("")

        # Full proposed options table
        lines.append("#### 📋 Full Proposed Options for Tier")
        lines.append("| Model ID | Display Name | Live Price ($In / $Out) | Context | Status | Rationale |")
        lines.append("| :--- | :--- | :--- | :--- | :--- | :--- |")

        for opt in tc.get("options", []):
            mid = opt.get("id", "")
            name = opt.get("name", mid)
            is_rec = opt.get("is_recommended", False)
            rat = opt.get("rationale", "")

            cat_item = catalog_map.get(mid)
            if cat_item:
                price_str = cat_item["price_str"]
                ctx_str = cat_item["ctx_str"]
            else:
                price_str = "Live API"
                ctx_str = "1M Context"

            badge = "**⭐ Recommended**" if is_rec else "Alternative"
            lines.append(f"| `{mid}` | {name} | **{price_str}** | {ctx_str} | {badge} | {rat} |")
        lines.append("\n---\n")

    lines.append("## 💡 Maintainer Action Items")
    lines.append("- [ ] Review proposed model replacements and pricing deltas above.")
    lines.append("- [ ] Verify context window requirements (1M context preserved for agentic flows).")
    lines.append("- [ ] Merge this PR to update the default curated recommendations in `claude-threepio`.")

    return "\n".join(lines)

def apply_comparative_recommendations(analysis_result, catalog_map, today_str, setup_path="claude-threepio"):
    if not os.path.exists(setup_path):
        warn(f"{setup_path} not found.")
        return

    info(f"Applying comparative tier recommendations to {setup_path}...")
    with open(setup_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Extract existing ollama blocks so they are not wiped out
    current_tiers = extract_current_tiers(setup_path)
    ollama_by_tier = {t["tier_name"]: t.get("ollama_block") for t in current_tiers}

    tier_blocks = []
    for tc in analysis_result.get("tier_comparisons", []):
        tname = tc.get("tier_name", "")
        opts_code = []
        for opt in tc.get("options", []):
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
        ollama_code = ""
        if ollama_by_tier.get(tname):
            ollama_code = f',\n            "ollama_options": {ollama_by_tier[tname]}'

        block = f"""        {{
            "tier_name": "{tname}",
            "tier_label": "{tc.get('tier_label')}",
            "claude_name": "{tc.get('claude_name')}",
            "options": [
{opts_str}
            ]{ollama_code}
        }}"""
        tier_blocks.append(block)

    all_tiers_code = "    tiers = [\n" + ",\n".join(tier_blocks) + "\n    ]"

    updated = re.sub(
        r"    tiers = \[\n.*?    \]",
        all_tiers_code,
        content,
        flags=re.DOTALL
    )


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
        warn("No OPENROUTER_API_KEY found. Live LLM comparative analysis requires an API key.")
        sys.exit(1)

    current_tiers = extract_current_tiers("claude-threepio")
    info(f"Extracted {len(current_tiers)} active tiers from claude-threepio for comparative baseline.")

    catalog = fetch_openrouter_catalog()
    if not catalog:
        sys.exit(1)

    catalog_map, compact_catalog = build_compact_catalog(catalog)

    analysis_result = perform_llm_comparative_analysis(api_key, current_tiers, catalog_map, compact_catalog, today_str)
    if not analysis_result:
        error("Could not obtain valid comparative analysis from LLM.")
        sys.exit(1)

    report_md = generate_comparative_markdown_report(analysis_result, current_tiers, catalog_map, today_str)
    report_file = "MODEL_RECOMMENDATIONS_REPORT.md"
    with open(report_file, "w", encoding="utf-8") as f:
        f.write(report_md)
    success(f"Wrote comprehensive comparative evaluation report to {report_file}")

    if apply_mode:
        apply_comparative_recommendations(analysis_result, catalog_map, today_str, "claude-threepio")

if __name__ == "__main__":
    main()
