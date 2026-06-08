# DeepSeek GUI X Edition

> Extended DeepSeek GUI with multi-provider support — use **any OpenAI-compatible API** (GLM, Qwen, Ollama, OpenRouter, etc.) alongside the original DeepSeek models.

---

> **Get 10% OFF Z.ai Coding Plans** — Access the latest GLM models for coding with an exclusive discount.
>
> 👉 **[Claim Your 10% OFF →](https://z.ai/subscribe?ic=ROK78RJKNW)**
>
> Power your development with state-of-the-art AI models — from code generation to full-stack apps.

---

## What Is This

DeepSeek GUI X Edition is a patched and configured version of the [DeepSeek GUI](https://github.com/deepseek-ai) desktop application (Electron + Kun runtime). It extends the original to support **any OpenAI-compatible API provider** — not just DeepSeek.

This project was created with the assistance of **GLM 5.1** — using one AI model to enable support for others in a desktop application that wasn't designed for it.

### Key Changes

| Area | Change |
|------|--------|
| **Multi-Provider Launcher** | Interactive CLI to add providers, select models, and launch the GUI with correct config |
| **URL Routing** | Patched Kun's `buildUrl()` to handle versioned base URLs (e.g., `/v4`) that don't use `/v1/` prefix |
| **Model Profiles** | Dynamic model profile generation for any provider's models in Kun config |
| **Provider Registry** | Extended GUI settings to list custom models in the model selector dropdown |
| **Binary Override** | Uses `binaryPath` setting to load patched Kun runtime from a permanent location |

## Multi-Provider Launcher

The **DSGUI Launcher** is a portable Python CLI that lets you add multiple AI providers and switch between them easily. It handles all the config patching for you — no manual JSON editing needed.

Works on **Linux**, **macOS**, and **WSL2**. No dependencies (pure Python).

### Install

```bash
# Clone this repo
git clone https://github.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition.git

# Add the alias to your shell
echo "alias dsgui='python3 $(pwd)/DeepSeek-GUI-X-Edition/launcher/dsgui-launcher.py'" >> ~/.bashrc
source ~/.bashrc
```

### Quick Start

```bash
# First time: add your providers
dsgui --add
# Enter provider name, base URL, API key
# Models are auto-discovered from the /models endpoint

# Launch interactively
dsgui
```

You'll see:
```
  ╔═══════════════════════════════════════════╗
  ║    DeepSeek GUI — Multi-Provider Launcher  ║
  ╚═══════════════════════════════════════════╝

  Select Provider
  ────────────────────────────────────────
  1) zai (7 models)
  2) qwen (10 models)

  3) Add provider
  4) Remove provider
  5) Add custom model
  6) Quit

  >
```

Pick provider → pick model → it patches the config and launches the GUI.

### CLI Commands

| Command | Description |
|---------|-------------|
| `dsgui` | Interactive menu: select provider & model, then launch |
| `dsgui --add` | Add a new provider (auto-discovers models) |
| `dsgui --remove` | Remove a provider |
| `dsgui --list` | List all configured providers & models |
| `dsgui --model` | Add a custom model to an existing provider |
| `dsgui --quick <name>` | Quick-launch with first model from provider |
| `dsgui --help` | Show help |

### Adding Providers

You can add any OpenAI-compatible API:

```bash
dsgui --add
# Provider name: zai
# Base URL: https://api.z.ai/api/coding/paas/v4
# API Key: your-key-here
# → Auto-discovers: glm-5.1, glm-5-turbo, glm-5, ...

dsgui --add
# Provider name: ollama
# Base URL: http://localhost:11434/v1
# API Key: none
# → Auto-discovers: llama3, mistral, ...

dsgui --add
# Provider name: openrouter
# Base URL: https://openrouter.ai/api/v1
# API Key: sk-or-...
# → Auto-discovers: all available models
```

### Platform-Specific Notes

**Linux (AppImage):**
- The launcher auto-detects `~/Applications/DeepSeek-GUI.AppImage`
- Launches with `--no-sandbox` flag
- Works on Ubuntu, Fedora, Arch, etc.

**macOS:**
- Auto-detects `~/Applications/DeepSeek GUI.app` or `/Applications/DeepSeek GUI.app`
- Config paths: `~/Library/Application Support/deepseek-gui/`

**WSL2 (Windows Subsystem for Linux):**
- Same as Linux — the launcher detects WSL2 automatically
- Make sure DeepSeek GUI is installed inside WSL2
- Alternatively, point `gui_executable` to the Windows binary if running GUI on Windows side

### How It Works

The launcher patches DeepSeek GUI's `deepseek-gui-settings.json` at **two levels** before launching:

```
provider.baseUrl       ← what Kun runtime reads (API endpoint)
provider.apiKey        ← what Kun runtime reads (auth key)

provider.providers[0].baseUrl   ← what the dropdown UI reads
provider.providers[0].apiKey    ← what the dropdown UI reads
provider.providers[0].models    ← what models appear in the selector

agents.kun.model       ← pre-selects the model
```

It also generates Kun model profiles in `kun/config.json` for each model with correct context windows and compaction thresholds.

## Manual Installation (Without Launcher)

If you prefer to set things up manually:

```bash
# 1. Create patched Kun directory
mkdir -p ~/.deepseekgui/kun-patched/dist/adapters/model

# 2. Copy Kun files from your existing installation
APPIMAGE_KUN="<your-appimage-path>/resources/app.asar.unpacked/kun"
cp -r "$APPIMAGE_KUN/dist" ~/.deepseekgui/kun-patched/
cp -r "$APPIMAGE_KUN/node_modules" ~/.deepseekgui/kun-patched/
cp "$APPIMAGE_KUN/package.json" ~/.deepseekgui/kun-patched/ 2>/dev/null

# 3. Apply the buildUrl patch
cp patches/deepseek-compat-model-client.patched.js \
   ~/.deepseekgui/kun-patched/dist/adapters/model/deepseek-compat-model-client.js

# 4. Copy the Kun config with model profiles
cp config/kun-config.json ~/.deepseekgui/kun/config.json

# 5. Update GUI settings (see config/gui-settings.json for reference)
```

## Architecture

```
┌─────────────────────────────────┐
│     DSGUI Launcher (CLI)        │
│  Select provider + model        │
│  Patch GUI settings (2 levels)  │
│  Patch Kun model profiles       │
└──────────┬──────────────────────┘
           │ patches config, then launches
           ▼
┌─────────────────────────────────┐
│         DeepSeek GUI            │
│         (Electron app)          │
│  deepseek-gui-settings.json     │
│    binaryPath → kun-patched     │
│    provider models → custom     │
└──────────┬──────────────────────┘
           │ spawns Kun with --base-url
           ▼
┌─────────────────────────────────┐
│      Kun Runtime (patched)      │
│  buildUrl() versioned-URL fix   │
│  Custom model profiles          │
│                                 │
│  Works with ANY /vN endpoint:   │
│  /v1/chat/completions ✓         │
│  /v4/chat/completions ✓         │
│  /beta/v1/chat/completions ✓    │
└──────────┬──────────────────────┘
           │ HTTP POST
           ▼
┌─────────────────────────────────┐
│    Any OpenAI-Compatible API    │
│  z.ai, Qwen, Ollama, OpenRouter │
│  DeepSeek, custom servers, etc. │
└─────────────────────────────────┘
```

## Project Structure

```
DeepSeek-GUI-X-Edition/
├── launcher/                        # Multi-Provider Launcher
│   ├── dsgui-launcher.py            # Interactive CLI launcher
│   └── providers.json               # Provider config (auto-generated)
├── patches/                         # Patch files and diffs
│   ├── buildUrl-fix.patch           # Core URL routing fix (unified diff)
│   ├── deepseek-compat-model-client.original.js
│   └── deepseek-compat-model-client.patched.js
├── config/                          # Configuration reference files
│   ├── kun-config.json              # Kun runtime config with model profiles
│   └── gui-settings.json            # GUI settings reference
├── docs/                            # Documentation
│   ├── ROOT-CAUSE-ANALYSIS.md       # Detailed root cause of each issue
│   ├── GLM-INTEGRATION-GUIDE.md     # Step-by-step provider integration guide
│   └── PROOF-OF-WORK.md             # Real API responses as evidence
├── tests/                           # Test documentation
│   └── TEST_REPORT.md               # Verification tests and results
├── scripts/                         # Helper scripts
│   └── install.py                   # Automated installation script
├── CHANGELOG.md                     # Version history
├── LICENSE                          # MIT License
└── README.md                        # This file
```

## The Core Fix

The critical fix is a 10-line patch to `buildUrl()` in `deepseek-compat-model-client.js`:

```javascript
// BEFORE: Always appended /v1/chat/completions
buildUrl(path) {
    const base = this.config.baseUrl.replace(/\/+$/, '');
    return `${base}${path}`;
}
// Result: https://api.z.ai/api/coding/paas/v4/v1/chat/completions → 404

// AFTER: Detects versioned URLs and adjusts path
buildUrl(path) {
    const base = this.config.baseUrl.replace(/\/+$/, "");
    if (path === "/v1/chat/completions") {
        if (base.endsWith("/chat/completions"))
            return base;
        const versioned = /\/v\d+$/.test(base);
        if (versioned)
            return `${base}/chat/completions`;
    }
    return `${base}${path}`;
}
// Result: https://api.z.ai/api/coding/paas/v4/chat/completions → 200
```

## Supported Models

Based on the **custom provider you add**, you will be able to use that provider's models. For example, after adding the **Z.ai** endpoint (`https://api.z.ai/api/coding/paas/v4`), I could use these models:

| Model | Provider | Context Window | Tool Calling | Streaming |
|-------|----------|---------------|-------------|-----------|
| glm-5.1 | Z.ai | 128,000 | ✓ | ✓ |
| glm-5-turbo | Z.ai | 128,000 | ✓ | ✓ |
| glm-5 | Z.ai | 128,000 | ✓ | ✓ |
| glm-4.7 | Z.ai | 128,000 | ✓ | ✓ |
| glm-4.6 | Z.ai | 128,000 | ✓ | ✓ |
| glm-4.5 | Z.ai | 128,000 | ✓ | ✓ |
| glm-4.5-air | Z.ai | 128,000 | ✓ | ✓ |

> **Want access to GLM models?** [Get 10% OFF your Z.ai Coding Plan →](https://z.ai/subscribe?ic=ROK78RJKNW)

The same approach works for any other OpenAI-compatible provider — add your provider via the launcher and start chatting.

## Credits

- Built on top of [DeepSeek GUI](https://github.com/deepseek-ai) by DeepSeek
- GLM models powered by [z.ai](https://z.ai)
- This X Edition was created with the assistance of GLM 5.1

## License

MIT
