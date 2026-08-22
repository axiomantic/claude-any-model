# claude-threepio

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](https://claude.ai)
[![OpenRouter](https://img.shields.io/badge/OpenRouter-API-purple.svg)](https://openrouter.ai)
[![Claude Desktop](https://img.shields.io/badge/Claude%20Desktop-3P%20Inference-orange.svg)](https://claude.ai)
[![Release](https://img.shields.io/github/v/release/axiomantic/claude-threepio?include_prereleases&color=green)](https://github.com/axiomantic/claude-threepio/releases)

Keep coding in Claude Desktop and Claude Code after you hit your weekly Claude credit limit — without the prohibitive overage costs.

---

## Why This Exists

You're on a Claude Max plan. You hit your weekly credit limit. The work isn't done. Your options:

1. **Pay Claude overage rates** — $15-25 per million output tokens. A full day of coding can cost hundreds of dollars.
2. **Switch to a different coding harness** (OpenCode, Cursor, Pi) with less expensive open-weight models — but you lose your active session context, project state, and sidebar when you jump tools.
3. **Stop working.**

None of these are good. This project exists for option four:

4. **Stay in Claude Code and Claude Desktop. Route requests to cheaper models on OpenRouter** — at 80-95% lower cost. Your sessions, projects, sidebar, and workflow don't change. This tool maps each Claude tier (Opus, Sonnet, Haiku, etc.) to a recommended equivalent model automatically, or you can pick your own custom model for any tier.

A typical day of coding that would cost $50-200+ in Claude overage costs $2-5 on OpenRouter with equivalent-quality models.

---

## How It Works

Claude Desktop has two modes: **First-Party Mode (1P)** — your normal subscription, Anthropic models, Anthropic billing — and **Third-Party Mode (3P)**, intended for enterprise deployments (AWS Bedrock, Vertex AI, etc.). Out of the box, 3P only supports Anthropic models — you pick *where* they're hosted, not *which* models.

`claude-threepio` uses 3P as the entry point and swaps in any model:

1. **Claude Desktop or CLI** sends requests to a lightweight local gateway (`http://127.0.0.1:3010`).
2. **Local Proxy (LiteLLM)** translates Anthropic Messages API calls and forwards them to your selected models on OpenRouter.
3. **Live pricing** appears directly in Claude's model picker — you see cost per token before you pick.

On macOS, 3P runs from `~/Library/Application Support/Claude-3p/`. On Linux, `~/.config/Claude-3p/`. Your 1P mode stays untouched — you switch between them with one command.

---

## Quick Start

Run the installer:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/axiomantic/claude-threepio/main/install.sh)"
```

*(Or clone the repository and run `./claude-threepio install`)*

> [!NOTE]
> **Third-Party Mode Differences**: Because 3P mode routes inference through local proxy endpoints rather than Anthropic's proprietary cloud relay, certain Anthropic cloud-specific features such as `/remote-control` (mobile app session steering via `claude.ai/code`) do not function in 3P mode. Simply switch back to 1P mode (`./claude-threepio switch regular`) whenever you need native remote-control capabilities.

---

## Model Selection & Tiers

`claude-threepio` maps Anthropic tiers (**Opus**, **Sonnet**, **Haiku**, **Fable**, and **Mythos**) to curated, high-efficiency models with real-time pricing and capabilities fetched live from OpenRouter:

* **Paid Workhorses**: Top-ranking models for reasoning, agentic tool use, and coding (e.g. DeepSeek V4 Pro, Gemini 3.7 Flash, Qwen 3.7 Flash, GLM-5.2) at 80–95% lower cost than Claude overages.
* **$0.00 Free Models**: Curated zero-cost community models from [OpenRouter's Free Collection](https://openrouter.ai/collections/free-models) (e.g. Nemotron 3 Ultra 550B, Ox Alpha, North Mini Code, Laguna S, Inkling Small).
* **Custom Models & Endpoints**: You can specify **any custom OpenRouter model ID** or connect directly to **any OpenAI-compatible endpoint** (local Ollama, LM Studio, vLLM, Aphrodite, LocalAI, or custom gateways).
* **Interactive 2-Pane TUI**: Run `./claude-threepio models` to launch the interactive selector. The left pane lists models grouped by provider, while the right pane shows real-time metadata, live pricing, context window length, 1M context agent support, and capability descriptions as you navigate.

For comparison, Claude's native overage rates are $15–$25 per million output tokens. Switching to high-throughput models like DeepSeek V4 Flash ($0.08/$0.15) or Qwen 3.7 Flash ($0.03/$0.13) reduces daily token expenses from $50–$100+ down to $1–$3.


---

## Switching Back to 1P

When your weekly Claude credits reset, switch back to your subscription:

```bash
./claude-threepio switch regular
```

Your sessions, sidebar, and project groupings are synced automatically during the switch so nothing is lost.

And when your usage runs out again, switch back to 3P:

```bash
./claude-threepio switch gateway
```

Check the active mode and proxy health at any time:
```bash
./claude-threepio status
```

---

## CLI Commands

```bash
./claude-threepio install            # Full setup: venv, API key, model picker, daemon
./claude-threepio launch             # Launch Claude CLI routed through the local proxy
./claude-threepio models             # Reconfigure tier models (live OpenRouter prices)
./claude-threepio switch [mode]      # Switch between 1P (regular) and 3P (proxy) mode
./claude-threepio sync-sessions      # Merge sessions and sidebar groupings between 1P and 3P
./claude-threepio status             # Check active mode, daemon health, and 3P profile
./claude-threepio restart            # Restart local gateway daemon
./claude-threepio uninstall          # Stop and remove background service
```

---

## Using with Claude CLI (Claude Code)

### Recommended: use the built-in launcher

```bash
./claude-threepio launch
```

This sets the correct env vars and `exec`s into `claude` — no need to remember export commands.

### Manual launch

```bash
ANTHROPIC_BASE_URL="http://127.0.0.1:3010" ANTHROPIC_API_KEY="dummy-key" claude
```

Or add to your shell profile for a persistent alias:

```bash
# ~/.zshrc or ~/.bashrc
alias claude-proxy='ANTHROPIC_BASE_URL="http://127.0.0.1:3010" ANTHROPIC_API_KEY="dummy-key" claude'
```

---

## License

This project is licensed under the [MIT License](LICENSE).
