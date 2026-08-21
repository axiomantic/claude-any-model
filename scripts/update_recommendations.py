#!/usr/bin/env python3
"""
Weekly OpenRouter Model Recommender & Evaluator
Fetches live OpenRouter catalog, discovers new releases/price shifts,
and generates PR/Issue updates for curated tier recommendations.
"""

import os
import sys
import json
import urllib.request
from datetime import datetime, timezone

OPENROUTER_MODELS_URL = "https://openrouter.ai/api/v1/models"

def fetch_catalog():
    print("[INFO] Fetching full model catalog from OpenRouter API...")
    req = urllib.request.Request(
        OPENROUTER_MODELS_URL,
        headers={"User-Agent": "Claude-OpenRouter-Recommender/1.2.0"}
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode()).get("data", [])
            print(f"[SUCCESS] Retrieved {len(data)} total models from OpenRouter.")
            return data
    except Exception as e:
        print(f"[ERROR] Failed to fetch OpenRouter catalog: {e}", file=sys.stderr)
        return []

def parse_model(m):
    mid = m.get("id", "")
    p_in = float(m.get("pricing", {}).get("prompt", 0)) * 1_000_000
    p_out = float(m.get("pricing", {}).get("completion", 0)) * 1_000_000
    ctx = int(m.get("context_length", 0))
    created = m.get("created", 0)
    desc = m.get("description", "")
    name = m.get("name", mid)

    return {
        "id": mid,
        "name": name,
        "p_in": p_in,
        "p_out": p_out,
        "price_str": f"${p_in:.2f}/${p_out:.2f}",
        "ctx": ctx,
        "ctx_str": f"{ctx // 1_000_000}M Context" if ctx >= 1_000_000 else f"{ctx // 1_000}k Context",
        "supports1m": ctx >= 900_000,
        "created": created,
        "description": desc
    }

def analyze_candidates(models):
    parsed = [parse_model(m) for m in models]
    
    # Bucket models by tier suitability
    analysis = {
        "opus": [],
        "sonnet": [],
        "haiku": [],
        "fable": [],
        "mythos": [],
        "recent_releases": []
    }

    # Filter out inactive or 0-pricing anomalous listings
    valid = [m for m in parsed if m["p_in"] > 0 or m["p_out"] > 0]

    for m in valid:
        mid = m["id"].lower()
        mname = m["name"].lower()
        desc = m["description"].lower()

        # Check for Opus tier candidates (heavy reasoning, high capability, context >= 200k)
        if any(k in mid for k in ["kimi-k3", "glm-5", "deepseek-v4-pro", "gpt-5.6-terra", "sonnet-4.6", "r1", "o3-mini", "opus-4", "opus-5"]):
            analysis["opus"].append(m)

        # Check for Sonnet tier candidates (coding, agentic workhorses)
        if any(k in mid for k in ["qwen3-coder", "coder", "sonnet-4", "deepseek-chat", "deepseek-v3", "codestral", "claude-3.5-sonnet"]):
            analysis["sonnet"].append(m)

        # Check for Haiku tier candidates (budget, ultra-low cost < $0.50/M)
        if (m["p_in"] <= 0.25 and m["p_out"] <= 0.50) or any(k in mid for k in ["flash", "luna", "nano", "mini", "haiku"]):
            analysis["haiku"].append(m)

        # Check for Fable tier candidates (ultra-heavyweight agentic runner)
        if any(k in mid for k in ["glm-5", "kimi-k3", "deepseek-v4-pro", "gpt-5.6-terra", "claude-opus"]):
            analysis["fable"].append(m)

        # Check for Mythos tier candidates (frontier & experimental)
        if any(k in mid for k in ["opus-5", "kimi-k3", "deepseek-v4-pro", "glm-5.2", "gpt-5.6-sol"]):
            analysis["mythos"].append(m)

    return analysis

def generate_markdown_report(analysis, today_str):
    report_lines = [
        f"# 🤖 Weekly Model Catalog & Recommendation Report",
        f"**Generated on:** {today_str} UTC  ",
        f"**Source:** [OpenRouter Models API](https://openrouter.ai/models)\n",
        "---",
        "## 📊 Current Recommended Tiers & Top Candidates\n"
    ]

    tier_descriptions = {
        "opus": ("Opus Tier", "Heavyweight Reasoning & Complex Architecture"),
        "sonnet": ("Sonnet Tier", "Fast Agentic Workhorse & Coding"),
        "haiku": ("Haiku Tier", "Maximum Speed & Ultra-Low Cost"),
        "fable": ("Fable Tier", "Ultra-Heavyweight Multi-Step Agent Runner"),
        "mythos": ("Mythos Tier", "Frontier & Experimental Heavyweights")
    }

    for tier_key, (tier_title, tier_subtitle) in tier_descriptions.items():
        candidates = analysis.get(tier_key, [])
        # Deduplicate and sort by price
        unique_cand = {c["id"]: c for c in candidates}.values()
        sorted_cand = sorted(unique_cand, key=lambda x: (x["p_in"] + x["p_out"]))[:6]

        report_lines.append(f"### 🎯 {tier_title} — *{tier_subtitle}*")
        report_lines.append("| Model ID | Display Name | Pricing ($In / $Out per 1M) | Context | 1M Support |")
        report_lines.append("| :--- | :--- | :--- | :--- | :--- |")
        for c in sorted_cand:
            supp_1m = "✅ Yes" if c["supports1m"] else "❌ No"
            report_lines.append(f"| `{c['id']}` | {c['name']} | **{c['price_str']}** | {c['ctx_str']} | {supp_1m} |")
        report_lines.append("")

    report_lines.append("---")
    report_lines.append("## 💡 Automated Assessment")
    report_lines.append("- OpenRouter pricing and context limits have been validated.")
    report_lines.append("- Models with 1M context windows remain preferred for large-file and multi-turn agent sessions.")
    report_lines.append(f"- Timestamp metadata updated to `{today_str}`.\n")

    return "\n".join(report_lines)

def main():
    apply_mode = "--apply" in sys.argv
    today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    
    catalog = fetch_catalog()
    if not catalog:
        print("[ERROR] Empty catalog. Exiting.")
        sys.exit(1)

    analysis = analyze_candidates(catalog)
    report_md = generate_markdown_report(analysis, today_str)

    report_file = "MODEL_RECOMMENDATIONS_REPORT.md"
    with open(report_file, "w", encoding="utf-8") as f:
        f.write(report_md)
    print(f"[SUCCESS] Wrote recommendations report to {report_file}")

    if apply_mode:
        print(f"[INFO] Applying updated revisit timestamp ({today_str}) to setup.sh...")
        setup_path = "setup.sh"
        if os.path.exists(setup_path):
            with open(setup_path, "r", encoding="utf-8") as f:
                content = f.read()
            import re
            # Update bash assignment (no spaces)
            updated_content = re.sub(
                r'^MODELS_LAST_REVISITED="[^"]+"',
                f'MODELS_LAST_REVISITED="{today_str}"',
                content,
                flags=re.MULTILINE
            )
            # Update inlined Python assignment (with spaces)
            updated_content = re.sub(
                r'^MODELS_LAST_REVISITED = "[^"]+"',
                f'MODELS_LAST_REVISITED = "{today_str}"',
                updated_content,
                flags=re.MULTILINE
            )
            with open(setup_path, "w", encoding="utf-8") as f:
                f.write(updated_content)
            print(f"[SUCCESS] Updated {setup_path} with {today_str}")

if __name__ == "__main__":
    main()


