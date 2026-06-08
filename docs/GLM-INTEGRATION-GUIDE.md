# GLM Provider Integration Guide

## How We Made DeepSeek GUI Open to Other Providers

This guide documents the step-by-step process of extending the DeepSeek GUI to support GLM models from z.ai. This was done with the assistance of **GLM 5.1** itself — using one model to enable support for another.

### Background

The DeepSeek GUI is an Electron desktop application that wraps a "Kun" runtime — a Node.js-based agent runtime that communicates with LLM APIs via OpenAI-compatible chat completions endpoints. It was designed exclusively for DeepSeek models.

The goal: make it work with GLM models served at `https://api.z.ai/api/coding/paas/v4`.

---

### Step 1: Understand the Architecture

**Discovery process:**
1. Located the configuration at `~/.config/deepseek-gui/deepseek-gui-settings.json`
2. Found Kun's data directory at `~/.deepseekgui/kun/`
3. Examined the Kun config at `~/.deepseekgui/kun/config.json`
4. Identified the error logs at `~/.config/deepseek-gui/logs/`
5. Read thread event logs at `~/.deepseekgui/kun/threads/*/events.jsonl`

**Key insight**: The system has 3 configuration layers:
- **GUI settings** (`deepseek-gui-settings.json`) — model list, API key, base URL
- **Kun config** (`kun/config.json`) — model profiles, context windows, capabilities
- **Kun runtime binary** (`deepseek-compat-model-client.js`) — actual HTTP request logic

### Step 2: Verify API Compatibility

Tested the z.ai endpoint manually:
```bash
# List available models
curl https://api.z.ai/api/coding/paas/v4/models \
  -H "Authorization: Bearer $API_KEY"
# Returns: glm-5.1, glm-5-turbo, glm-5, glm-4.7, glm-4.6, glm-4.5, glm-4.5-air

# Test chat completions
curl -X POST https://api.z.ai/api/coding/paas/v4/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"glm-5.1","messages":[{"role":"user","content":"hi"}]}'
# Returns: 200 OK with valid response
```

**Result**: The API is OpenAI-compatible and works perfectly.

### Step 3: Add GLM Model Profiles to Kun Config

Edited `~/.deepseekgui/kun/config.json` to add model profiles for each GLM model:

```json
{
  "models": {
    "profiles": {
      "glm-5.1": {
        "contextWindowTokens": 128000,
        "contextCompaction": {
          "softThreshold": 120000,
          "hardThreshold": 124000
        },
        "inputModalities": ["text"],
        "outputModalities": ["text"],
        "supportsToolCalling": true,
        "messageParts": ["text"]
      }
    }
  }
}
```

### Step 4: Add GLM Models to GUI Provider

Updated `~/.config/deepseek-gui/deepseek-gui-settings.json`:

```json
{
  "provider": {
    "providers": [{
      "models": [
        "deepseek-v4-flash", "deepseek-v4-pro",
        "glm-5.1", "glm-5-turbo", "glm-5",
        "glm-4.7", "glm-4.6", "glm-4.5", "glm-4.5-air"
      ]
    }]
  }
}
```

### Step 5: Discover the URL Routing Bug

After Steps 3-4, the GUI still returned 404. The events.jsonl showed:
```
error: model request failed with status 404
```

**Investigation**:
1. Extracted the ASAR archive to read Kun's source code
2. Found `deepseek-compat-model-client.js` which constructs API URLs
3. Identified the `buildUrl()` method that concatenates `/v1/chat/completions` to the base URL
4. Tested all possible URL patterns against the z.ai API:
   - `/api/coding/paas/v4/chat/completions` → 200 ✓
   - `/api/coding/paas/v4/v1/chat/completions` → 404 ✗
   - `/v1/chat/completions` → 404 ✗

**Root cause**: Kun was producing `https://api.z.ai/api/coding/paas/v4/v1/chat/completions` because it blindly appended `/v1/chat/completions` to any base URL.

### Step 6: Patch the Kun Runtime

Modified `buildUrl()` in `deepseek-compat-model-client.js`:

```javascript
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
```

### Step 7: Deploy via binaryPath Override

Since the AppImage is read-only, we used the GUI's `binaryPath` setting to load the patched Kun from a permanent location:

```json
{
  "agents": {
    "kun": {
      "binaryPath": "/home/roman/.deepseekgui/kun-patched"
    }
  }
}
```

Copied the full Kun dist and node_modules to that location.

### Step 8: Verify

1. Restart the DeepSeek GUI
2. Select a GLM model from the dropdown
3. Send a message
4. Confirm response is received successfully

---

## Lessons Learned

1. **Always test the API directly** before assuming the issue is in configuration
2. **Read the source code** — ASAR archives can be extracted and inspected
3. **URL construction matters** — different providers use different URL conventions
4. **Use built-in override mechanisms** — `binaryPath` is cleaner than patching ASAR files
5. **Config files are dual-layered** — both Kun config and GUI settings need updating
