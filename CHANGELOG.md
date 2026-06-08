# Changelog

All notable changes to DeepSeek GUI X Edition are documented here.

## [1.1.0] - 2026-06-08

### Added
- **Multi-Provider Launcher** (`launcher/dsgui-launcher.py`)
  - Interactive terminal UI to select provider → model → launch GUI
  - Auto-discovery of models from any OpenAI-compatible `/models` endpoint
  - Add/remove providers and custom models from the CLI
  - Auto-detects DeepSeek GUI executable on Linux, macOS, and WSL2
  - Patches both levels of `deepseek-gui-settings.json` (top-level provider config AND provider array)
  - Generates Kun model profiles with correct context windows automatically
  - Kills existing GUI instance before relaunching with new config
  - Zero dependencies (pure Python, no pip install needed)
  - CLI commands: `dsgui`, `dsgui --add`, `dsgui --remove`, `dsgui --list`, `dsgui --model`, `dsgui --quick <name>`

### Fixed
- **"Kun turn failed" with custom providers**
  - Root cause: DeepSeek GUI uses a dual-level config — `provider.baseUrl` (what Kun reads) and `provider.providers[0].baseUrl` (what the dropdown reads). Only patching one level caused a mismatch where Kun would hit the wrong API endpoint
  - Fix: The launcher patches BOTH config levels simultaneously, ensuring the runtime endpoint and the UI always match
  - This eliminates all provider-switching errors regardless of which provider or model is selected

### Platform Support
- **Linux**: Auto-detects AppImage at `~/Applications/DeepSeek-GUI.AppImage`
- **macOS**: Auto-detects `.app` bundle in `~/Applications/` and `/Applications/`
- **WSL2**: Detected automatically, uses same Linux paths

## [1.0.0] - 2026-06-08

### Added
- **GLM Model Support**: Added support for all 7 z.ai GLM models (glm-5.1, glm-5-turbo, glm-5, glm-4.7, glm-4.6, glm-4.5, glm-4.5-air)
- **Multi-Provider Architecture**: Extended the provider configuration system to support multiple model families under a single API endpoint
- **Patched Kun Runtime**: Custom Kun binary with URL routing fix for non-standard API paths
- **Installation Script**: Automated setup script for configuring an existing DeepSeek GUI installation

### Fixed
- **HTTP 404 on GLM model requests** (Critical)
  - Root cause: Kun's `DeepseekCompatModelClient.buildUrl()` hardcoded `/v1/chat/completions` path, which when combined with z.ai's `https://api.z.ai/api/coding/paas/v4` baseUrl produced the invalid URL `https://api.z.ai/api/coding/paas/v4/v1/chat/completions` (404)
  - Fix: Modified `buildUrl()` to detect versioned base URLs ending in `/vN` and use `/chat/completions` directly instead of `/v1/chat/completions`
  - See: `patches/buildUrl-fix.patch`

- **Missing model profiles for GLM models** (Configuration)
  - Root cause: Kun's `config.json` only defined `deepseek-v4-pro` and `deepseek-v4-flash` model profiles; GLM models had no profile entries, causing routing failures
  - Fix: Added model profile entries for all 7 GLM models with appropriate context windows (128K), compaction thresholds, and tool calling support
  - See: `config/kun-config.json`

- **GLM models not appearing in model selector** (UI)
  - Root cause: GUI settings `provider.providers[0].models` array only listed DeepSeek model IDs
  - Fix: Extended the models array to include all GLM model IDs
  - Note: GUI may reset this on restart; the launcher handles re-injection
  - See: `config/gui-settings.json`

### Known Limitations
- The GUI settings file may be overwritten by the application on startup, requiring re-application of model entries (the launcher handles this automatically)
- The `binaryPath` override is required because the AppImage bundles Kun inside a read-only ASAR archive
- Only tested on Linux (Ubuntu 26.04) with the AppImage distribution
