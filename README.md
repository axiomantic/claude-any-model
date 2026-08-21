# Claude OpenRouter Models (`claude-openrouter-models`)

Route **Claude Desktop Third-Party Inference** requests to cost-effective models on **OpenRouter** (e.g. Kimi K3, Qwen3-Coder, DeepSeek V4 Flash, GLM-5.2) with live token pricing shown directly in Claude's model picker.

---

## ⚡ Quick Start (One-Liner)

```bash
curl -fsSL https://raw.githubusercontent.com/axiomantic/claude-openrouter-models/main/setup.sh | bash
```

*(Or clone the repository and run `./setup.sh install`)*

---

## 🧭 Curated Model Tiers

| Tier | Claude Alias | Recommended Target | Price (In / Out per 1M) | Context | Strength |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Opus** | `claude-opus-4` | **Kimi K3** (`moonshotai/kimi-k3`) | **$3.00 / $15.00** | 1M | 2.8T MoE Heavyweight Reasoning |
| **Sonnet** | `claude-sonnet-4-5` | **Qwen3 Coder Next** (`qwen/qwen3-coder-next`) | **$0.12 / $0.80** | 262k | Fast Agentic Coder Workhorse |
| **Haiku** | `claude-3-haiku-20240307` | **DeepSeek V4 Flash** (`deepseek/deepseek-v4-flash`) | **$0.08 / $0.17** | 1M | 13B Active MoE, Maximum Economy |
| **Fable** | `claude-fable-5` | **GLM-5.2** (`z-ai/glm-5.2`) | **$0.97 / $3.04** | 1M | 744B MoE Multi-Step Agent Runner |
| **Mythos** | `claude-mythos-1` | **Claude Opus 5 / Kimi K3 Ultra** | **$3.00 – $5.00** | 1M | Frontier Multi-Agent Coordination |

---

## ⚙️ How Gateway Mode Works in Claude Desktop

Claude Desktop supports local gateway proxies via its sandboxed third-party inference system (see [Anthropic Third-Party Inference Guide](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/third-party-llms)):

### Automated Configuration (Recommended)
Running `./setup.sh install` or `./setup.sh models` automatically configures both the LiteLLM proxy and Claude Desktop's active profile in `~/Library/Application Support/Claude-3p/configLibrary/`.

### Manual GUI Verification
If configuring or verifying via the Claude Desktop in-app menu (**Developer > Configure Third-Party Inference**):
* **Inference Provider:** `Gateway`
* **Inference Gateway Base URL:** `http://127.0.0.1:3010`
* **Inference Gateway API Key:** `dummy-key`
* **Credential Kind:** `Static`

> **Note:** Always quit Claude Desktop (**Cmd+Q**) before running `./setup.sh models` so Claude cleanly loads the updated profile on launch.

---

## 🛠️ CLI Commands

```bash
./setup.sh models     # Switch or reconfigure tier models (fetches live OpenRouter prices)
./setup.sh status     # Check background daemon health and active Claude 3P profile
./setup.sh restart    # Restart local gateway daemon
./setup.sh uninstall  # Stop and remove background service and proxy files
```

---

## ✨ Features

* **⚡ Real-Time API Pricing:** Queries `https://openrouter.ai/api/v1/models` dynamically for up-to-date pricing and context window sizes.
* **🏷️ In-App Pricing Labels:** Displays prices in Claude's model picker (e.g. `Kimi K3 ($3.00/$15.00) [1M]`).
* **🔄 Background Daemon:** Managed via macOS launchd (`com.claude-to-openrouter-proxy`).
* **🤖 Weekly Catalog Scans:** A weekly GitHub Action monitors OpenRouter releases, evaluates price shifts, and proposes updated recommendations via PRs.
