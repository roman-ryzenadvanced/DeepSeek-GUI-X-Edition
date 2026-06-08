# DeepSeek GUI X Edition

> Extended DeepSeek GUI with multi-provider support — enabling GLM models (glm-5.1, glm-5-turbo, glm-4.7, and more) from [z.ai](https://z.ai) alongside the original DeepSeek models.

---

> **Get 10% OFF Z.ai Coding Plans** — Access the latest GLM models for coding with an exclusive discount.
>
> 👉 **[Claim Your 10% OFF →](https://z.ai/subscribe?ic=ROK78RJKNW)**
>
> Power your development with state-of-the-art AI models — from code generation to full-stack apps.

---

## What Is This

DeepSeek GUI X Edition is a patched and configured version of the [DeepSeek GUI](https://github.com/deepseek-ai) desktop application (Electron + Kun runtime). It extends the original to support **any OpenAI-compatible API provider**, with specific fixes for the z.ai `api.z.ai` endpoint that serves GLM models.

This project was created with the assistance of **GLM 5.1** — using one AI model to enable support for others in a desktop application that wasn't designed for it.

### Key Changes

| Area | Change |
|------|--------|
| **URL Routing** | Patched Kun's `buildUrl()` to handle versioned base URLs (e.g., `/v4`) that don't use `/v1/` prefix |
| **Model Profiles** | Added GLM model profiles (glm-5.1, glm-5-turbo, glm-5, glm-4.7, glm-4.6, glm-4.5, glm-4.5-air) to Kun config |
| **Provider Registry** | Extended GUI settings to list GLM models in the model selector dropdown |
| **Binary Override** | Uses `binaryPath` setting to load patched Kun runtime from a permanent location |

## Quick Start

### Prerequisites

- DeepSeek GUI AppImage installed (e.g., `~/Applications/DeepSeek-GUI.AppImage`)
- z.ai API key with access to GLM models
- Linux (tested on Ubuntu 26.04)

### Installation

```bash
# 1. Clone this repo
git clone https://github.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition.git
cd DeepSeek-GUI-X-Edition

# 2. Run the installer (automates all setup)
python3 scripts/install.py --gui-settings ~/.config/deepseek-gui/deepseek-gui-settings.json
```

The installer will:
1. Copy the patched `deepseek-compat-model-client.js` to `~/.deepseekgui/kun-patched/dist/`
2. Add GLM model profiles to `~/.deepseekgui/kun/config.json`
3. Update GUI settings with GLM models and `binaryPath` override

### Manual Installation

If you prefer to set things up manually:

```bash
# 1. Create patched Kun directory
mkdir -p ~/.deepseekgui/kun-patched/dist/adapters/model

# 2. Copy Kun files from your existing installation
#    (Extract from AppImage or copy from the installed location)
APPIMAGE_KUN="<your-appimage-path>/resources/app.asar.unpacked/kun"
cp -r "$APPIMAGE_KUN/dist" ~/.deepseekgui/kun-patched/
cp -r "$APPIMAGE_KUN/node_modules" ~/.deepseekgui/kun-patched/
cp "$APPIMAGE_KUN/package.json" ~/.deepseekgui/kun-patched/ 2>/dev/null

# 3. Apply the buildUrl patch
cp patches/deepseek-compat-model-client.patched.js \
   ~/.deepseekgui/kun-patched/dist/adapters/model/deepseek-compat-model-client.js

# 4. Copy the Kun config with GLM profiles
cp config/kun-config.json ~/.deepseekgui/kun/config.json

# 5. Update GUI settings (see config/gui-settings.json for reference)
```

### Verify

Launch the GUI, open model selector — you should see GLM models listed alongside DeepSeek models.

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
├── patches/                         # Patch files and diffs
│   ├── buildUrl-fix.patch           # Core URL routing fix (unified diff)
│   ├── deepseek-compat-model-client.original.js   # Original unpatched file
│   └── deepseek-compat-model-client.patched.js    # Patched file
├── config/                          # Configuration files
│   ├── kun-config.json              # Kun runtime config with GLM profiles
│   └── gui-settings.json            # GUI settings reference with GLM models
├── docs/                            # Documentation
│   ├── ROOT-CAUSE-ANALYSIS.md       # Detailed root cause of each issue
│   ├── GLM-INTEGRATION-GUIDE.md     # Step-by-step GLM provider integration
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
| deepseek-v4-pro | DeepSeek | 1,000,000 | ✓ | ✓ |
| deepseek-v4-flash | DeepSeek | 1,000,000 | ✓ | ✓ |
| glm-5.1 | Z.ai | 128,000 | ✓ | ✓ |
| glm-5-turbo | Z.ai | 128,000 | ✓ | ✓ |
| glm-5 | Z.ai | 128,000 | ✓ | ✓ |
| glm-4.7 | Z.ai | 128,000 | ✓ | ✓ |
| glm-4.6 | Z.ai | 128,000 | ✓ | ✓ |
| glm-4.5 | Z.ai | 128,000 | ✓ | ✓ |
| glm-4.5-air | Z.ai | 128,000 | ✓ | ✓ |

> **Want access to GLM models?** [Get 10% OFF your Z.ai Coding Plan →](https://z.ai/subscribe?ic=ROK78RJKNW)

The same approach works for any other OpenAI-compatible provider — just update the base URL, add your models to the Kun config and GUI settings, and the patched runtime handles the rest.

## Credits

- Built on top of [DeepSeek GUI](https://github.com/deepseek-ai) by DeepSeek
- GLM models powered by [z.ai](https://z.ai)
- This X Edition was created with the assistance of GLM 5.1

## License

MIT
