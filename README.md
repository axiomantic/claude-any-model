# Claude Any Model

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](https://claude.ai)
[![OpenRouter](https://img.shields.io/badge/OpenRouter-API-purple.svg)](https://openrouter.ai)
[![Claude Desktop](https://img.shields.io/badge/Claude%20Desktop-3P%20Inference-orange.svg)](https://claude.ai)
[![Release](https://img.shields.io/github/v/release/axiomantic/claude-any-model?include_prereleases&color=green)](https://github.com/axiomantic/claude-any-model/releases)

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

`claude-any-model` uses 3P as the entry point and swaps in any model:

1. **Claude Desktop or CLI** sends requests to a lightweight local gateway (`http://127.0.0.1:3010`).
2. **Local Proxy (LiteLLM)** translates Anthropic Messages API calls and forwards them to your selected models on OpenRouter.
3. **Live pricing** appears directly in Claude's model picker — you see cost per token before you pick.

On macOS, 3P runs from `~/Library/Application Support/Claude-3p/`. On Linux, `~/.config/Claude-3p/`. Your 1P mode stays untouched — you switch between them with one command.

---

## Quick Start

Run the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/axiomantic/claude-any-model/main/claude-any-model | bash
```

*(Or clone the repository and run `./claude-any-model install`)*

---

## Model Tiers

Each Claude tier maps to a set of OpenRouter models. The recommended pick is marked with **bold**. Run `./claude-any-model models` to choose from these or set your own custom model.

| Tier | Best For | Model | Price (per 1M in/out) | Context |
|------|----------|-------|-----------------------|---------|
| Sonnet | Daily coding, agentic tasks | **Qwen3 Coder Next** | $0.12 / $0.80 | 262k |
| | | Claude Sonnet 4 | $3.00 / $15.00 | 1M |
| | | DeepSeek V3 | $0.26 / $1.03 | 163k |
| | | Qwen3 Coder Flash | $0.20 / $0.97 | 1M |
| Opus | Architecture, deep reasoning | **Kimi K3** | $3.00 / $15.00 | 1M |
| | | GLM-5.2 | $0.97 / $3.04 | 1M |
| | | GPT-5.6 Terra | $2.00 / $12.00 | 1M |
| | | DeepSeek V4 Pro | $1.19 / $3.56 | 1M |
| | | Claude Sonnet 4.6 | $3.00 / $15.00 | 1M |
| Haiku | Quick tasks, completions | **DeepSeek V4 Flash** | $0.08 / $0.17 | 1M |
| | | Gemini 2.0 Flash | $0.10 / $0.40 | 1M |
| | | Qwen3 Coder 30B | $0.07 / $0.28 | 262k |
| | | GPT-5.6 Luna | $0.20 / $1.20 | 1M |
| Fable | Multi-step agents, long context | **GLM-5.2** | $0.97 / $3.04 | 1M |
| | | Kimi K3 | $3.00 / $15.00 | 1M |
| | | DeepSeek V4 Pro | $1.19 / $3.56 | 1M |
| | | GPT-5.6 Terra | $2.00 / $12.00 | 1M |
| Mythos | Frontier, Claude-native | **Claude Opus 5** | $5.00 / $25.00 | 1M |
| | | Kimi K3 Ultra | $3.00 / $15.00 | 1M |
| | | DeepSeek V4 Pro (Max) | $1.19 / $3.56 | 1M |
| | | GLM-5.2 (Reasoning) | $0.97 / $3.04 | 1M |

For comparison, Claude's own overage rates are $15-25 per million output tokens. The Sonnet-tier Qwen3 Coder Next at $0.80 output is the main reason to use this project — a full day of coding that would cost ~$50-100 in overage costs roughly $1-3.

Local inference (Ollama, LM Studio, vLLM) is auto-discovered and offered as a free option at any tier.

---

## Switching Back to 1P

When your weekly Claude credits reset, switch back to your subscription:

```bash
./claude-any-model switch regular
```

Your sessions, sidebar, and project groupings are synced automatically during the switch so nothing is lost.

And when your usage runs out again, switch back to 3P:

```bash
./claude-any-model switch gateway
```

Check the active mode and proxy health at any time:
```bash
./claude-any-model status
```

---

## CLI Commands

```bash
./claude-any-model install            # Full setup: venv, API key, model picker, daemon
./claude-any-model launch             # Launch Claude CLI routed through the local proxy
./claude-any-model models             # Reconfigure tier models (live OpenRouter prices)
./claude-any-model switch [mode]      # Switch between 1P (regular) and 3P (proxy) mode
./claude-any-model sync-sessions      # Merge sessions and sidebar groupings between 1P and 3P
./claude-any-model status             # Check active mode, daemon health, and 3P profile
./claude-any-model restart            # Restart local gateway daemon
./claude-any-model uninstall          # Stop and remove background service
```

---

## Using with Claude CLI (Claude Code)

### Recommended: use the built-in launcher

```bash
./claude-any-model launch
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
