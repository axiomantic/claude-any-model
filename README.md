# Claude OpenRouter Models

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://apple.com)
[![OpenRouter](https://img.shields.io/badge/OpenRouter-API-purple.svg)](https://openrouter.ai)
[![Claude Desktop](https://img.shields.io/badge/Claude%20Desktop-3P%20Inference-orange.svg)](https://claude.ai)
[![Release](https://img.shields.io/github/v/release/axiomantic/claude-openrouter-models?include_prereleases&color=green)](https://github.com/axiomantic/claude-openrouter-models/releases)

Route Claude Desktop and Claude CLI requests to hundreds of models on OpenRouter (including Qwen3-Coder, DeepSeek V4 Flash, Kimi K3, and GLM-5.2) with live token pricing shown directly in Claude's model picker.

---

## What is This?

Many people don't know that Anthropic built a **Third-Party Inference** mode into Claude Desktop. This built-in feature allows Claude Desktop to connect to any custom API gateway instead of being locked to Anthropic's cloud servers.

`claude-openrouter-models` makes using this feature effortless:

* **Cut Costs by 80–95%**: Use top-tier coding and reasoning models (like Qwen3-Coder at $0.12/1M input tokens vs. Claude 3.5 Sonnet at $3.00/1M).
* **Live Pricing in the UI**: Shows real-time OpenRouter token prices directly in Claude Desktop's model picker dropdown (e.g., `Qwen3 Coder ($0.12/$0.80) [262k]`).
* **Keep the Claude UI**: You get the full official Claude Desktop experience (chat, artifacts, projects, code sessions) powered by OpenRouter's model catalog.
* **Works with Claude CLI**: Route terminal `claude` CLI coding sessions through the same local proxy.

### How It Works

1. **Claude Desktop or CLI** sends requests to a lightweight local gateway running on your machine (`http://127.0.0.1:3010`).
2. **Local Proxy (LiteLLM)** translates Anthropic Messages API requests and forwards them to your selected models on OpenRouter.
3. **Automated Catalog Sync**: Periodically fetches OpenRouter's live API catalog to update model aliases, context sizes, and pricing labels.

---

## Quick Start

Run the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/axiomantic/claude-openrouter-models/main/setup.sh | bash
```

*(Or clone the repository and run `./setup.sh install`)*

---

## Curated Model Tiers

| Tier | Claude Alias | Recommended Target | Price (In / Out per 1M) | Context | Strength |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Opus** | `claude-opus-4` | **Kimi K3** (`moonshotai/kimi-k3`) | **$3.00 / $15.00** | 1M | 2.8T MoE Heavyweight Reasoning |
| **Sonnet** | `claude-sonnet-4-5` | **Qwen3 Coder Next** (`qwen/qwen3-coder-next`) | **$0.12 / $0.80** | 262k | Fast Agentic Coder Workhorse |
| **Haiku** | `claude-3-haiku-20240307` | **DeepSeek V4 Flash** (`deepseek/deepseek-v4-flash`) | **$0.08 / $0.17** | 1M | 13B Active MoE, Maximum Economy |
| **Fable** | `claude-fable-5` | **GLM-5.2** (`z-ai/glm-5.2`) | **$0.97 / $3.04** | 1M | 744B MoE Multi-Step Agent Runner |
| **Mythos** | `claude-mythos-1` | **Claude Opus 5 / Kimi K3 Ultra** | **$3.00 – $5.00** | 1M | Frontier Multi-Agent Coordination |

---

## Gateway Mode Setup in Claude Desktop

### Automated Configuration (Recommended)

Running `./setup.sh install` or `./setup.sh models` automatically configures both the background gateway daemon and Claude Desktop's active profile in `~/Library/Application Support/Claude-3p/configLibrary/`.

### Manual GUI Verification

If verifying settings in Claude Desktop (**Developer > Configure Third-Party Inference**):
* **Inference Provider:** `Gateway`
* **Inference Gateway Base URL:** `http://127.0.0.1:3010`
* **Inference Gateway API Key:** `dummy-key`
* **Credential Kind:** `Static`

> **Note:** Always quit Claude Desktop (**Cmd+Q**) before running `./setup.sh models` so Claude cleanly loads the updated profile on launch.

---

## Migrating Existing Sessions to Gateway Mode

When transitioning from standard (Anthropic-direct) mode to Gateway mode, Claude Desktop switches to an isolated profile directory (`Claude-3p`), meaning your past sessions and sidebar projects will not appear by default.

### 1. Enable the Import Feature in Your 3P Profile

By default, Gateway mode disables the migration UI with the message:
> *"Import isn’t enabled for this deployment. Contact your organization’s administrator to turn it on."*

To unlock it:
* **Automatic:** Running `./setup.sh install` or `./setup.sh models` automatically enables this setting in your active profile.
* **Manual:** Add the `claudeAiImport` block to your active profile in `~/Library/Application Support/Claude-3p/configLibrary/<profile-id>.json`:
  ```json
  "claudeAiImport": {
    "enabled": true,
    "exportEnabled": true,
    "bannerBehavior": "detect"
  }
  ```

### 2. Import Your Sessions

1. Restart Claude Desktop in Gateway mode.
2. Open **Settings** (`Cmd + ,` on macOS) -> **Import**.
3. Select your local sources:
   * **Claude app data** (imports previous 1P Desktop chat and code sessions)
   * **Terminal (CLI)** (imports CLI sessions from `~/.claude/projects/`)
4. Click **Import**.

Your historical sessions, custom titles, and project groupings will immediately appear in your sidebar and search.

---

## CLI Commands

```bash
./setup.sh models     # Switch or reconfigure tier models (fetches live OpenRouter prices)
./setup.sh status     # Check background daemon health and active Claude 3P profile
./setup.sh restart    # Restart local gateway daemon
./setup.sh uninstall  # Stop and remove background service and proxy files
```

---

## Using with Claude CLI (Claude Code)

You can route the official `claude` terminal CLI through the same local proxy:

```bash
export ANTHROPIC_BASE_URL="http://127.0.0.1:3010"
export ANTHROPIC_API_KEY="dummy-key"
claude
```

The CLI will route requests to your configured OpenRouter models while preserving prompt caching and context management.

---

## Automated Model Recommendations (GitHub Actions)

A weekly GitHub Action evaluates the live OpenRouter catalog using benchmark data (SWE-bench, LiveBench, Chatbot Arena) and pricing shifts to automatically open PRs with updated model recommendations.

### Configuring the Repository Secret

To enable the weekly evaluation workflow in GitHub Actions, add your OpenRouter API key as a repository secret:

```bash
gh secret set OPENROUTER_API_KEY --repo axiomantic/claude-openrouter-models
```

*(Or configure it via the GitHub UI: **Settings > Secrets and variables > Actions > New repository secret**)*

---

## License

This project is licensed under the [MIT License](LICENSE).
