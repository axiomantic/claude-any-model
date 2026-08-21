# Claude OpenRouter Models (`claude-openrouter-models`)

A lightweight, automated local gateway proxy that seamlessly routes **Claude Desktop Third-Party Inference** requests to cost-effective models on **OpenRouter** (e.g. Kimi K3, Qwen3-Coder, DeepSeek V4 Flash, GLM-5.2, GPT-5.6 Terra, and more).

---

## ⚡ One-Liner Quick Start

You can install or reconfigure the gateway with a single terminal command:

```bash
curl -fsSL https://raw.githubusercontent.com/axiomantic/claude-openrouter-models/main/setup.sh | bash
```

*(Or if you have cloned the repository locally:)*
```bash
./setup.sh install
```


---

## 🌟 Key Features

* **⚡ Live OpenRouter API Pricing:** Automatically queries `https://openrouter.ai/api/v1/models` in real time to retrieve exact token pricing (`$In / $Out per 1M tokens`) and context window limits for every model option.
* **🎯 5 Anthropic Family Tiers:** Curated model options for **Opus**, **Sonnet**, **Haiku**, **Fable**, and **Mythos**.
* **✍️ Custom Model Write-In:** Enter any arbitrary OpenRouter model ID slug (e.g., `moonshotai/kimi-k3`, `openai/gpt-5.6-terra`) with automatic API price detection.
* **🏷️ Model Labels with Live Pricing:** Automatically updates Claude Desktop's model picker with pricing visible directly in the model name (e.g., `Kimi K3 ($3.00/$15.00) [1M]`).
* **🛡️ Sandboxed Claude 3P Synchronization:** Directly updates Claude Desktop's hidden `configLibrary` active profile and checks if Claude Desktop is closed before applying edits to prevent file corruption.
* **🔄 Seamless Background Daemon:** Installs and manages a background macOS LaunchAgent service (`com.claude-to-openrouter-proxy`).
* **📂 Automated Backups & Clean Migration:** Preserves timestamped backups of `config.yaml` and `<UUID>.json` before modifications, and seamlessly migrates legacy `.litellm-proxy` directories.

---

## 🧭 Anthropic Tier Mapping

| Tier | Claude Desktop Identifier | Recommended Model | Pricing (In / Out per 1M) | Context | Primary Strength |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Opus** | `claude-opus-4` | **Kimi K3** (`moonshotai/kimi-k3`) | $3.00 / $15.00 | 1M | 2.8T MoE Heavyweight Reasoning & Complex Architecture |
| **Sonnet** | `claude-sonnet-4-5` | **Qwen3 Coder Next** (`qwen/qwen3-coder-next`) | $0.12 / $0.80 | 262k | Fast Agentic Workhorse & Dedicated Coding Specialist |
| **Haiku** | `claude-3-haiku-20240307` | **DeepSeek V4 Flash** (`deepseek/deepseek-v4-flash`) | $0.08 / $0.17 | 1M | 13B Active MoE, Maximum Speed & Ultra-Low Cost |
| **Fable** | `claude-fable-5` | **GLM-5.2** (`z-ai/glm-5.2`) | $1.40 / $4.40 | 1M | 744B MoE Ultra-Heavyweight Multi-Step Agent Runner |
| **Mythos** | `claude-mythos-1` | **Claude Opus 5 / Kimi K3 Ultra** | $3.00 – $5.00+ | 1M | Frontier Multi-Agent Coordination & Deep Reasoning |

---

## 🛠️ CLI Commands

`setup.sh` includes helper subcommands for day-to-day management:

```bash
# Switch or reconfigure models at any time (fetches live OpenRouter prices)
./setup.sh models

# Check proxy daemon status, local gateway health, and active Claude profile
./setup.sh status

# Restart the local proxy daemon
./setup.sh restart

# Start or Stop the proxy daemon
./setup.sh start
./setup.sh stop

# Print version
./setup.sh version

# Completely remove launchd service and proxy configuration
./setup.sh uninstall
```

---

## 📂 System Architecture & Paths

```text
~/.claude-to-openrouter-proxy/
├── .env                  # OpenRouter API Key and port configuration (mode 600)
├── config.yaml           # LiteLLM routing rules mapping Claude tiers to OpenRouter IDs
├── run_proxy.sh          # Executable runner script for background daemon
├── venv/                 # Python 3 virtual environment with LiteLLM & FastAPI
└── logs/
    ├── litellm.out.log   # Gateway stdout
    └── litellm.err.log   # Gateway stderr

~/Library/LaunchAgents/
└── com.claude-to-openrouter-proxy.plist # macOS startup daemon (runs on boot)

~/Library/Application Support/Claude-3p/configLibrary/
├── _meta.json            # Records active Claude 3P profile ID
└── <UUID>.json           # Active gateway config, baseURL (http://127.0.0.1:3010), and model labels
```

---

## 🔍 How Claude Desktop 3P Inference Works

When third-party inference is enabled in Claude Desktop, settings are stored inside `~/Library/Application Support/Claude-3p/configLibrary/` rather than standard preferences:

1. `_meta.json` specifies the active profile UUID.
2. `<UUID>.json` holds the gateway URL (`http://127.0.0.1:3010`), static dummy key, and `inferenceModels` mapping.
3. `setup.sh` synchronizes LiteLLM's `config.yaml` and Claude's `<UUID>.json` simultaneously, ensuring that model aliases sent by Claude Desktop map 1-to-1 to OpenRouter targets.

---

## ❓ Troubleshooting

### 1. Claude Desktop shows configuration error
* Ensure Claude Desktop was completely closed when running `./setup.sh models` or `./setup.sh install`. Claude Desktop locks and rewrites its configuration files on exit.

### 2. "This request requires more credits, or fewer max_tokens"
* Check your OpenRouter dashboard at [openrouter.ai/settings/credits](https://openrouter.ai/settings/credits).
* In OpenRouter, go to **Workspaces > Default > API Keys**, inspect your key's **Weekly Limit**, and ensure it has sufficient balance allocated for high-context token requests.

### 3. Checking Proxy Logs
View real-time proxy traffic and errors:
```bash
tail -f ~/.claude-to-openrouter-proxy/logs/litellm.err.log
tail -f ~/.claude-to-openrouter-proxy/logs/litellm.out.log
```
