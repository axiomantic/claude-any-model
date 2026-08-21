# Claude Any Model

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://apple.com)
[![OpenRouter](https://img.shields.io/badge/OpenRouter-API-purple.svg)](https://openrouter.ai)
[![Claude Desktop](https://img.shields.io/badge/Claude%20Desktop-3P%20Inference-orange.svg)](https://claude.ai)
[![Release](https://img.shields.io/github/v/release/axiomantic/claude-any-model?include_prereleases&color=green)](https://github.com/axiomantic/claude-any-model/releases)

Route Claude Desktop and Claude CLI requests to hundreds of models on OpenRouter (including Qwen3-Coder, DeepSeek V4 Flash, Kimi K3, and GLM-5.2) with live token pricing shown directly in Claude's model picker.

---

## What is This?

Anthropic includes a **Third-Party Inference** mode in Claude Desktop designed for enterprise deployments (such as AWS Bedrock, Google Cloud Vertex AI, or private VPCs). However, out of the box, this feature is strictly limited to **Anthropic models** — you can choose *where* your Claude models are hosted, but you are still locked into official Anthropic models at standard pricing.

`claude-any-model` breaks this lock-in:

* **Use Any Model in Claude Desktop**: Seamlessly maps Claude's model picker to hundreds of models on OpenRouter (including Qwen3-Coder, DeepSeek V4 Flash, Kimi K3, GLM-5.2, Llama 3.3, and Mistral).
* **Cut Inference Costs by 80–95%**: Run state-of-the-art coding and reasoning models at pennies per million tokens (e.g., Qwen3-Coder at $0.12/1M input vs. Claude 3.5 Sonnet at $3.00/1M).
* **Live Pricing in the Model Picker**: Displays real-time OpenRouter token pricing and context window limits directly in Claude Desktop's dropdown UI (e.g., `Qwen3 Coder ($0.12/$0.80) [262k]`).
* **Keep Native Claude Features**: Full support for chat history, markdown artifacts, project folders, code execution sessions, and file attachments.
* **Works with Claude CLI**: Route terminal `claude` CLI coding sessions through the same local proxy.

### How It Works

1. **Claude Desktop or CLI** sends requests to a lightweight local gateway running on your machine (`http://127.0.0.1:3010`).
2. **Local Proxy (LiteLLM)** translates Anthropic Messages API requests and forwards them to your selected models on OpenRouter.
3. **Automated Catalog Sync**: Periodically fetches OpenRouter's live API catalog to update model aliases, context sizes, and pricing labels.

---

## Quick Start

Run the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/axiomantic/claude-any-model/main/setup.sh | bash
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

## Universal Providers & Local Inference (Ollama, LM Studio, vLLM)

In addition to OpenRouter's cloud catalog, you can route Claude Desktop and Claude CLI to **local offline inference engines**:

* **Ollama Auto-Discovery**: If Ollama is running (`http://localhost:11434`), `./setup.sh models` automatically detects your installed models (e.g., `qwen2.5-coder`, `deepseek-r1`) and makes them selectable with `$0.00 / Local` pricing.
* **LM Studio & vLLM**: Connects to any local OpenAI-compatible endpoint on custom ports (`http://localhost:1234/v1` or `http://localhost:8000/v1`).
* **Hybrid / Mix & Match**: Assign local models for unlimited free coding iterations (Sonnet / Haiku tiers) while routing heavyweight architectural queries to OpenRouter (Opus tier).

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

## Switching Between Gateway Mode and Regular Claude

You can toggle between **Gateway Mode** (OpenRouter proxy) and **Regular Claude** (official Anthropic account) with a single command:

```bash
# Toggle between Gateway and Regular Claude
./setup.sh switch

# Or explicitly switch to a specific mode:
./setup.sh switch regular    # Reverts Claude Desktop to native Anthropic Pro/Team
./setup.sh switch gateway    # Activates OpenRouter proxy mode
```

Check the active mode and proxy health at any time:
```bash
./setup.sh status
```

---

## CLI Commands

```bash
./setup.sh switch [mode] # Toggle or switch mode ('gateway' or 'regular')
./setup.sh models        # Switch or reconfigure tier models (fetches live OpenRouter prices)
./setup.sh status        # Check active mode, background daemon health and Claude 3P profile
./setup.sh restart       # Restart local gateway daemon
./setup.sh uninstall     # Stop and remove background service and proxy files
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
gh secret set OPENROUTER_API_KEY --repo axiomantic/claude-any-model
```

*(Or configure it via the GitHub UI: **Settings > Secrets and variables > Actions > New repository secret**)*

---

## License

This project is licensed under the [MIT License](LICENSE).
