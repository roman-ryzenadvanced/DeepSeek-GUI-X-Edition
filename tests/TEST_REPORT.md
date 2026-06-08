# Test Report — DeepSeek GUI X Edition v1.0.0

**Date**: 2026-06-08  
**Environment**: Ubuntu 26.04, DeepSeek GUI AppImage, z.ai API

---

## Test 1: API Endpoint Verification

**Purpose**: Verify that the z.ai API endpoint responds to chat completion requests.

| Test | URL | Method | Expected | Result |
|------|-----|--------|----------|--------|
| T1.1 | `/api/coding/paas/v4/chat/completions` | POST | 200 | PASS |
| T1.2 | `/api/coding/paas/v4/v1/chat/completions` | POST | 404 | PASS (confirmed 404) |
| T1.3 | `/api/coding/paas/v4/models` | GET | 200 | PASS |

**Models returned**: glm-4.5, glm-4.5-air, glm-4.6, glm-4.7, glm-5, glm-5-turbo, glm-5.1

## Test 2: GLM Model Chat Completion

**Purpose**: Verify each GLM model can respond to a basic prompt.

| Model | Prompt | Status | Response |
|-------|--------|--------|----------|
| glm-5.1 | "hi" | 200 | Valid response with reasoning_content |
| glm-5-turbo | "hi" | 200 | Valid response |

## Test 3: buildUrl() Patch Correctness

**Purpose**: Verify the patched `buildUrl()` method produces correct URLs for various baseUrl patterns.

| Input baseUrl | Input path | Expected Output | Result |
|---------------|-----------|-----------------|--------|
| `https://api.z.ai/api/coding/paas/v4` | `/v1/chat/completions` | `https://api.z.ai/api/coding/paas/v4/chat/completions` | PASS |
| `https://api.deepseek.com/beta` | `/v1/chat/completions` | `https://api.deepseek.com/beta/v1/chat/completions` | PASS |
| `https://api.example.com/v1` | `/v1/chat/completions` | `https://api.example.com/v1/chat/completions` | PASS |
| `https://api.example.com/chat/completions` | `/v1/chat/completions` | `https://api.example.com/chat/completions` | PASS |
| `https://api.z.ai/api/coding/paas/v1` | `/v1/chat/completions` | `https://api.z.ai/api/coding/paas/v1/chat/completions` | PASS |

## Test 4: Kun Config Validation

**Purpose**: Verify kun/config.json is valid JSON with all model profiles.

| Check | Result |
|-------|--------|
| Valid JSON | PASS |
| deepseek-v4-pro profile present | PASS |
| deepseek-v4-flash profile present | PASS |
| glm-5.1 profile present | PASS |
| glm-5-turbo profile present | PASS |
| glm-5 profile present | PASS |
| glm-4.7 profile present | PASS |
| glm-4.6 profile present | PASS |
| glm-4.5 profile present | PASS |
| glm-4.5-air profile present | PASS |
| All GLM profiles have supportsToolCalling: true | PASS |
| All GLM profiles have contextWindowTokens: 128000 | PASS |

## Test 5: GUI Settings Validation

**Purpose**: Verify gui-settings.json contains GLM models in provider list.

| Check | Result |
|-------|--------|
| Valid JSON | PASS |
| binaryPath set to kun-patched | PASS |
| GLM models in provider.models array | PASS |
| DeepSeek models still present | PASS |

## Test 6: Patched Kun Runtime Integrity

**Purpose**: Verify the patched Kun runtime files are complete and functional.

| Check | Result |
|-------|--------|
| serve-entry.js exists | PASS |
| deepseek-compat-model-client.js contains patch | PASS |
| Patch uses versioned-URL detection regex | PASS |
| Original path `/v1/chat/completions` still handled | PASS |

---

## Summary

| Category | Tests | Passed | Failed |
|----------|-------|--------|--------|
| API Verification | 3 | 3 | 0 |
| Model Response | 2 | 2 | 0 |
| URL Routing | 5 | 5 | 0 |
| Config Validation | 11 | 11 | 0 |
| Settings Validation | 4 | 4 | 0 |
| Runtime Integrity | 4 | 4 | 0 |
| **Total** | **29** | **29** | **0** |

All tests passed.
