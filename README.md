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

Claude Desktop has a built-in **Third-Party Inference** mode (called **3P mode**) intended for enterprise deployments (AWS Bedrock, Vertex AI, etc.). Out of the box, 3P mode only supports Anthropic models — you pick *where* they're hosted, not *which* models.

`claude-any-model` uses 3P mode as the entry point and swaps in any model:

1. **Claude Desktop or CLI** sends requests to a lightweight local gateway (`http://127.0.0.1:3010`).
2. **Local Proxy (LiteLLM)** translates Anthropic Messages API calls and forwards them to your selected models on OpenRouter.
3. **Live pricing** appears directly in Claude's model picker — you see cost per token before you pick.

On macOS, 3P mode runs from `~/Library/Application Support/Claude-3p/`. On Linux, `~/.config/Claude-3p/`. The regular (1P) mode you're used to stays untouched — you switch between them with one command.

---

## Quick Start

Run the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/axiomantic/claude-any-model/main/claude-any-model | bash
```

*(Or clone the repository and run `./claude-any-model install`)*

---

## Model Recommendations

Each Claude tier is mapped to a recommended OpenRouter model. The tier names are what Claude Desktop and Claude Code send internally — you'll see them in the model picker with live pricing.

### Daily coding (Sonnet tier)

The workhorse tier. What you'll use 90% of the time for coding, agentic tasks, and iteration.

**Qwen3 Coder Next** — `$0.12 input / $0.80 output per 1M tokens` — 262k context

Compared to Claude Sonnet at `$3.00 / $15.00`, a full day of coding that would cost ~$50-100 in Claude overage costs roughly $1-3 here. This is the main reason to use this project.

### Heavy reasoning (Opus tier)

For architecture decisions, complex debugging, and deep analysis where you'd normally reach for Opus.

**Kimi K3** — `$3.00 / $15.00` — 1M context

Priced the same as Claude Opus 4 but with a 1M context window. Use when Sonnet-tier models aren't cutting it.

### Quick tasks (Haiku tier)

Fast and cheap. Code completions, simple questions, formatting.

**DeepSeek V4 Flash** — `$0.08 / $0.17` — 1M context

Costs so little it's effectively free. A million output tokens for 17 cents.

### Multi-step agents (Fable tier)

For multi-step agent workflows that need sustained reasoning across long contexts.

**GLM-5.2** — `$0.97 / $3.04` — 1M context

A mid-range option that balances cost and capability for agentic runs.

### Frontier (Mythos tier)

When you want the absolute best available, or need native Claude compatibility for a specific task.

**Claude Opus 5** — `$5.00 / $25.00` — 1M context

This is Claude itself via OpenRouter. Use when you need guaranteed Claude behavior and are OK paying for it.

### Local inference (all tiers)

If Ollama is running, `./claude-any-model models` auto-discovers your local models and offers them as free alternatives at any tier. LM Studio and vLLM are also supported on any OpenAI-compatible endpoint.

---

## Gateway Mode Setup in Claude Desktop

Gateway mode is Claude Desktop's **3P mode** (Third-Party Inference) configured to route through the local proxy. Regular mode (1P) uses your native Anthropic account directly.

### Automated Configuration (Recommended)

Running `./claude-any-model install` or `./claude-any-model models` automatically configures both the background gateway daemon (launchd on macOS, systemd user service on Linux) and Claude Desktop's 3P profile. The 3P config directory is `~/Library/Application Support/Claude-3p/configLibrary/` on macOS, or `~/.config/Claude-3p/configLibrary/` on Linux.

### Manual GUI Verification

If verifying settings in Claude Desktop (**Developer > Configure Third-Party Inference**):
* **Inference Provider:** `Gateway`
* **Inference Gateway Base URL:** `http://127.0.0.1:3010`
* **Inference Gateway API Key:** `dummy-key`
* **Credential Kind:** `Static`

---

## Switching Between Gateway Mode and Regular Claude

You can toggle between **Gateway Mode** (3P — OpenRouter proxy) and **Regular Claude** (1P — official Anthropic account) with a single command:

```bash
# Toggle between Gateway (3P) and Regular (1P) Claude
./claude-any-model switch

# Or explicitly switch to a specific mode:
./claude-any-model switch regular    # Reverts Claude Desktop to native Anthropic Pro/Team (1P)
./claude-any-model switch gateway    # Activates OpenRouter proxy mode (3P)
```

Both modes prompt you to sync sessions and sidebar groupings so your session history, titles, and categories stay mirrored across modes. You can also sync manually at any time:

```bash
./claude-any-model sync-sessions
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
./claude-any-model switch [mode]      # Toggle between 'gateway' and 'regular' Claude mode
./claude-any-model sync-sessions      # Merge sessions and sidebar groupings between 1P and 3P modes
./claude-any-model status             # Check active mode, daemon health, and Claude 3P profile
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
