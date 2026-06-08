# Root Cause Analysis

## Issue 1: "Kun turn failed" — HTTP 404 on All GLM Model Requests

### Symptom
When sending any message to a GLM model (glm-5.1, glm-5-turbo, etc.) through the DeepSeek GUI, the request fails immediately with:
```
error: model request failed with status 404
code: http_404
```

The turn lifecycle shows:
```
input_routed → input_compressed → pre_send → post_send → error (404) → turn_failed
```

### Root Cause

**File**: `kun/dist/adapters/model/deepseek-compat-model-client.js`  
**Method**: `DeepseekCompatModelClient.buildUrl(path)` (line 76-79)

```javascript
// ORIGINAL CODE:
buildUrl(path) {
    const base = this.config.baseUrl.replace(/\/+$/, '');
    return `${base}${path}`;
}
```

This method is called with `path = "/v1/chat/completions"` (hardcoded at line 36).

**The problem**: When the baseUrl is `https://api.z.ai/api/coding/paas/v4`:
```
base  = "https://api.z.ai/api/coding/paas/v4"
path  = "/v1/chat/completions"
result = "https://api.z.ai/api/coding/paas/v4/v1/chat/completions"  → 404!
```

The z.ai API endpoint expects: `https://api.z.ai/api/coding/paas/v4/chat/completions`  
The `/v1/` segment is part of the standard OpenAI API convention but z.ai's `/v4` endpoint already includes versioning.

**Evidence**: Manual curl tests confirmed:
```bash
# This works:
curl https://api.z.ai/api/coding/paas/v4/chat/completions  → 200

# This does NOT work (what Kun was sending):
curl https://api.z.ai/api/coding/paas/v4/v1/chat/completions  → 404
```

### Fix

Modified `buildUrl()` to detect when the baseUrl already ends with a version segment (e.g., `/v4`) and skip the `/v1/` prefix:

```javascript
// PATCHED CODE:
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

**Logic**:
1. If the base URL already ends with `/chat/completions`, return as-is
2. If the base URL ends with a version segment (`/v4`, `/v1`, etc.), append `/chat/completions` directly
3. Otherwise, use the original behavior (`/v1/chat/completions`)

This maintains backward compatibility with the original DeepSeek API (`https://api.deepseek.com/beta`) while fixing z.ai compatibility.

---

## Issue 2: GLM Models Not Recognized by Kun Runtime

### Symptom
Even after selecting a GLM model in the GUI, Kun would route the request but fail because the model had no profile configuration.

### Root Cause

**File**: `~/.deepseekgui/kun/config.json`  
**Section**: `models.profiles`

The original config only defined two model profiles:

```json
{
  "models": {
    "profiles": {
      "deepseek-v4-pro": { ... },
      "deepseek-v4-flash": { ... }
    }
  }
}
```

When Kun received a request for `glm-5.1`, it had no profile to match against, which could cause routing issues or default to incorrect parameters.

### Fix

Added profile entries for all 7 GLM models with appropriate settings:
```json
"glm-5.1": {
    "contextWindowTokens": 128000,
    "contextCompaction": { "softThreshold": 120000, "hardThreshold": 124000 },
    "inputModalities": ["text"],
    "outputModalities": ["text"],
    "supportsToolCalling": true,
    "messageParts": ["text"]
}
```

---

## Issue 3: GLM Models Not Visible in GUI Model Selector

### Symptom
GLM models don't appear in the model dropdown in the DeepSeek GUI interface.

### Root Cause

**File**: `~/.config/deepseek-gui/deepseek-gui-settings.json`  
**Section**: `provider.providers[0].models`

The GUI builds its model selector from this array, which only contained:
```json
["deepseek-v4-flash", "deepseek-v4-pro"]
```

### Fix

Extended the array to include all GLM models:
```json
["deepseek-v4-flash", "deepseek-v4-pro", "glm-5.1", "glm-5-turbo", "glm-5", "glm-4.7", "glm-4.6", "glm-4.5", "glm-4.5-air"]
```

**Caveat**: The GUI may reset this list on restart. The install script handles re-injection.

---

## Issue 4: Patched Kun Not Loaded from AppImage

### Symptom
After patching files in `app.asar.unpacked/`, the changes were not picked up when launching from the AppImage.

### Root Cause

The GUI is packaged as an AppImage (read-only FUSE mount). Kun's JavaScript files are loaded from inside the ASAR archive, not from `app.asar.unpacked/` (which only holds native `.node` binaries). Patching the unpacked directory had no effect because Kun's entry point (`serve-entry.js`) and all JS modules were loaded from the ASAR.

### Fix

Used the GUI's built-in `binaryPath` configuration option to override where Kun is loaded from:

```json
{
  "agents": {
    "kun": {
      "binaryPath": "~/.deepseekgui/kun-patched"
    }
  }
}
```

When `binaryPath` is set to a directory, the GUI's `resolveKunExecutable()` function looks for `dist/cli/serve-entry.js` inside that directory, completely bypassing the bundled ASAR archive.
