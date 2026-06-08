# DeepSeek GUI X Edition

> Extended DeepSeek GUI with multi-provider support — use **any OpenAI-compatible AI provider** (z.ai/GLM, DeepSeek, Ollama, OpenRouter, vLLM, LM Studio, etc.) with an interactive terminal launcher.

## What Is This

DeepSeek GUI X Edition is a patched and configured version of the [DeepSeek GUI](https://github.com/XingYu-Zhong/DeepSeek-GUI) desktop application (Electron + Kun runtime). It extends the original to support **any OpenAI-compatible API provider**, with specific fixes for the z.ai `api.z.ai` endpoint that serves GLM models.

### Key Changes

| Area | Change |
|------|--------|
| **CLI Launcher** | Interactive `dsgui` launcher: add any provider, auto-discover models, launch GUI with one command |
| **URL Routing** | Patched Kun's `buildUrl()` to handle versioned base URLs (e.g., `/v4`) that don't use `/v1/` prefix |
| **Model Profiles** | Added GLM model profiles (glm-5.1, glm-5-turbo, glm-5, glm-4.7, glm-4.6, glm-4.5, glm-4.5-air) to Kun config |
| **Provider Registry** | Extended GUI settings to list GLM models in the model selector dropdown |
| **Binary Override** | Uses `binaryPath` setting to load patched Kun runtime from a permanent location |

---

## Quick Start: `dsgui` Launcher (Recommended)

The easiest way to use DeepSeek GUI X Edition with **any AI provider** is the `dsgui` launcher. It provides an interactive terminal menu to add providers, auto-discover models, and launch the GUI with the right configuration -- all automatically.

```bash
# Clone this repo
git clone https://github.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition.git
cd DeepSeek-GUI-X-Edition

# Set up the launcher
cp launcher/dsgui-launcher.py ~/.deepseekgui/dsgui-launcher.py
cp launcher/providers.json.example ~/.deepseekgui/providers.json

# Add alias (add to ~/.bashrc or ~/.zshrc)
alias dsgui='python3 ~/.deepseekgui/dsgui-launcher.py'

# Launch!
dsgui
```

### Launcher Commands

| Command | Description |
|---------|-------------|
| `dsgui` | Interactive menu: pick provider & model, launch GUI |
| `dsgui --add` | Add a new provider (name, base URL, API key, auto-discover models) |
| `dsgui --remove` | Remove a configured provider |
| `dsgui --list` | List all providers and their models |
| `dsgui --model` | Add a custom model to an existing provider |
| `dsgui --quick zai` | Quick-launch with first model from provider "zai" |

### How It Works

1. You add providers with `--add` (name, base URL, API key)
2. The launcher **auto-discovers available models** from the provider's `/models` endpoint
3. You pick a provider and model from the interactive menu
4. The launcher **patches GUI settings and Kun config** automatically with the selected provider/model
5. It **launches DeepSeek GUI** with the correct configuration

Works with **any OpenAI-compatible API**: z.ai (GLM), DeepSeek, Ollama, OpenRouter, vLLM, LM Studio, and more.

### Example: Add z.ai provider

```
$ dsgui --add
  Provider name: zai
  Base URL: https://api.z.ai/api/coding/paas/v4
  API Key: your-key-here
  Discovering models...
  Found 7 models (12 total)
  Use discovered models? [Y/n]: Y
  Provider 'zai' added with 7 models.
```

Then just run `dsgui`, pick "zai", pick "glm-5.1", and the GUI launches ready to go.

---

## Install from Source

These scripts clone the upstream [DeepSeek-GUI](https://github.com/XingYu-Zhong/DeepSeek-GUI) repo, apply the X Edition patches, and build the application locally.

### Prerequisites

- **Node.js 20+** and npm
- **git**
- **Python 3** (for config patching scripts)
- Platform-specific: see [upstream build docs](https://github.com/XingYu-Zhong/DeepSeek-GUI#local-build)

### Linux / macOS

```bash
# Clone this repo
git clone https://github.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition.git
cd DeepSeek-GUI-X-Edition

# Run the installer (clones upstream, patches, builds)
bash install.sh

# Or with options:
bash install.sh --skip-build          # Apply patches only, don't build
bash install.sh --build-dir ~/dev/DeepSeek-GUI  # Custom build location
```

**What it does:**
1. Clones `XingYu-Zhong/DeepSeek-GUI` into `/tmp/deepseek-gui-build`
2. Patches `buildUrl()` in Kun runtime for versioned URL support
3. Adds GLM model profiles to Kun config
4. Runs `npm install && npm run build && npm run dist:linux` (or `dist:mac`)
5. Outputs a built AppImage / .dmg

### Windows

```powershell
# Clone this repo
git clone https://github.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition.git
cd DeepSeek-GUI-X-Edition

# Run the installer
.\install.ps1

# Or with options:
.\install.ps1 -SkipBuild
.\install.ps1 -BuildDir C:\dev\DeepSeek-GUI
```

**What it does:**
1. Clones `XingYu-Zhong/DeepSeek-GUI` into `%TEMP%\deepseek-gui-build`
2. Patches `buildUrl()` in Kun runtime for versioned URL support
3. Adds GLM model profiles to Kun config
4. Runs `npm install && npm run build && npm run dist:win`
5. Outputs a built .exe installer

### Post-Build Configuration

After launching the built app for the first time, apply the GLM model settings:

**Linux / macOS:**
```bash
python3 scripts/install.py --gui-settings ~/.config/deepseek-gui/deepseek-gui-settings.json
```

**Windows:**
```powershell
python scripts/install.py --gui-settings "$env:APPDATA\DeepSeek GUI\deepseek-gui-settings.json"
```

This adds GLM models to the GUI model selector and sets the `binaryPath` to the patched Kun runtime.

---

## Quick Start (Existing DeepSeek GUI Installation)

If you already have DeepSeek GUI installed (e.g., via AppImage), you can patch it without rebuilding by using the pre-built patched Kun runtime.

**Step 1: Get the patched Kun runtime**

Option A — Build from upstream source:
```bash
git clone https://github.com/XingYu-Zhong/DeepSeek-GUI.git /tmp/deepseek-gui-build
cd /tmp/deepseek-gui-build
# Apply the buildUrl patch (see patches/buildUrl-fix.patch)
# Then build Kun: npm install && npm run build
```

Option B — Clone this X Edition repo and build Kun:
```bash
git clone https://github.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition.git
cd DeepSeek-GUI-X-Edition
bash install.sh --skip-build
# kun-dist and kun-node_modules will be in the upstream build
```

**Step 2: Patch an existing DeepSeek GUI installation**
```bash
# Copy the patched Kun runtime to a permanent location
mkdir -p ~/.deepseekgui/kun-patched
cp -r /tmp/deepseek-gui-build/kun/dist ~/.deepseekgui/kun-patched/dist
cp -r /tmp/deepseek-gui-build/kun/node_modules ~/.deepseekgui/kun-patched/node_modules

# Copy the patched config
cp config/kun-config.json ~/.deepseekgui/kun/config.json

# Patch GUI settings
python3 scripts/install.py --gui-settings ~/.config/deepseek-gui/deepseek-gui-settings.json

# Restart DeepSeek GUI
```

---

## Architecture

```
┌─────────────────────────────────┐
│         DeepSeek GUI            │
│         (Electron app)          │
│  deepseek-gui-settings.json     │
│    binaryPath → kun-patched     │
│    provider models → GLM+DS     │
└──────────┬──────────────────────┘
           │ spawns Kun with --base-url
           ▼
┌─────────────────────────────────┐
│      Kun Runtime (patched)      │
│  buildUrl() versioned-URL fix   │
│  GLM model profiles in config   │
│                                 │
│  baseUrl: api.z.ai/.../v4       │
│  → /v4/chat/completions ✓       │
│  (not /v4/v1/chat/completions)  │
└──────────┬──────────────────────┘
           │ HTTP POST
           ▼
┌─────────────────────────────────┐
│        z.ai API Endpoint        │
│  api.z.ai/api/coding/paas/v4    │
│  Models: glm-5.1, glm-5-turbo,  │
│  glm-4.7, deepseek-v4-*         │
└─────────────────────────────────┘
```

## Project Structure

```
DeepSeek-GUI-X-Edition/
├── install.sh                      # Linux/macOS source installer
├── install.ps1                     # Windows source installer
├── launcher/                       # Multi-provider CLI launcher
│   ├── dsgui-launcher.py            # Interactive provider/model selector + launcher
│   └── providers.json.example       # Sample providers config template
├── patches/                        # Patch files and diffs
│   ├── buildUrl-fix.patch          # Core URL routing fix
│   ├── deepseek-compat-model-client.original.js
│   └── deepseek-compat-model-client.patched.js
├── config/                         # Configuration files
│   ├── kun-config.json             # Kun runtime config with GLM profiles
│   └── gui-settings.json           # GUI settings with GLM models
├── scripts/                        # Helper scripts
│   ├── install.py                  # GUI settings patcher
│   └── patch-kun-config.py         # Kun config merger
├── docs/                           # Documentation
│   ├── ROOT-CAUSE-ANALYSIS.md      # Detailed root cause of each issue
│   └── GLM-INTEGRATION-GUIDE.md   # Step-by-step GLM provider integration
├── tests/                          # Test documentation
├── CHANGELOG.md                    # Version history
├── LICENSE                         # MIT License
└── README.md                       # This file
```

## Supported Models

| Model | Provider | Context Window | Tool Calling |
|-------|----------|---------------|-------------|
| deepseek-v4-pro | DeepSeek | 1,000,000 | ✓ |
| deepseek-v4-flash | DeepSeek | 1,000,000 | ✓ |
| glm-5.1 | z.ai | 128,000 | ✓ |
| glm-5-turbo | z.ai | 128,000 | ✓ |
| glm-5 | z.ai | 128,000 | ✓ |
| glm-4.7 | z.ai | 128,000 | ✓ |
| glm-4.6 | z.ai | 128,000 | ✓ |
| glm-4.5 | z.ai | 128,000 | ✓ |
| glm-4.5-air | z.ai | 128,000 | ✓ |

## Credits

- Built on top of [DeepSeek GUI](https://github.com/XingYu-Zhong/DeepSeek-GUI) by XingYu-Zhong
- GLM models powered by [z.ai](https://z.ai)
- This X Edition was created with the assistance of GLM 5.1

## License

MIT
