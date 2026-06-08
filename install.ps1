#Requires -Version 5.1
<#
.SYNOPSIS
    DeepSeek GUI X Edition - Windows Source Installer

.DESCRIPTION
    Clones upstream DeepSeek-GUI, applies X Edition patches (buildUrl fix,
    GLM model profiles), builds from source, and produces a runnable .exe installer.

.PARAMETER SkipBuild
    Skip npm build (apply patches only to existing clone)

.PARAMETER BuildDir
    Custom build directory (default: $env:TEMP\deepseek-gui-build)

.EXAMPLE
    .\install.ps1
    .\install.ps1 -SkipBuild -BuildDir C:\dev\DeepSeek-GUI

.NOTES
    Requires: Node.js 20+, npm, git
#>

param(
    [switch]$SkipBuild,
    [string]$BuildDir = "$env:TEMP\deepseek-gui-build"
)

# --- Config ---
$UpstreamRepo = "https://github.com/XingYu-Zhong/DeepSeek-GUI.git"
$ErrorActionPreference = "Stop"

# --- Helpers ---
function Write-Info  { Write-Host "[INFO]  " -ForegroundColor Blue -NoNewline; Write-Host @args }
function Write-Ok    { Write-Host "[OK]    " -ForegroundColor Green -NoNewline; Write-Host @args }
function Write-Warn  { Write-Host "[WARN]  " -ForegroundColor Yellow -NoNewline; Write-Host @args }
function Write-Fail  { Write-Host "[FAIL]  " -ForegroundColor Red -NoNewline; Write-Host @args; exit 1 }

# --- Check prerequisites ---
Write-Info "Checking prerequisites..."

$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) { Write-Fail "Node.js is not installed. Install Node.js 20+ from https://nodejs.org" }
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npmCmd) { Write-Fail "npm is not installed." }

$nodeVersion = [int]($nodeCmd.Version.ToString().Split(".")[0])
if ($nodeVersion -lt 20) { Write-Fail "Node.js 20+ required. Found: $($nodeCmd.Version)" }

Write-Ok "Node.js $($nodeCmd.Version)"
Write-Ok "npm $($npmCmd.Version)"

# --- Locate X Edition patches ---
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Get-Location }

if (-not (Test-Path "$ScriptDir\patches") -or -not (Test-Path "$ScriptDir\config")) {
    # Check if running from within the X Edition repo
    $ScriptDir = Get-Location
    if (-not (Test-Path "$ScriptDir\patches") -or -not (Test-Path "$ScriptDir\config")) {
        Write-Fail @"
Cannot find X Edition patches directory. Clone the repo first:
  git clone https://github.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition.git
  cd DeepSeek-GUI-X-Edition
  .\install.ps1
"@
    }
}
$PatchDir = $ScriptDir

# --- Clone or update upstream ---
Write-Info "Cloning upstream DeepSeek-GUI into $BuildDir..."

if (Test-Path "$BuildDir\.git") {
    Write-Info "Existing clone found, pulling latest..."
    Push-Location $BuildDir
    try { git pull --ff-only } catch { Write-Warn "Git pull failed, using existing clone" }
    Pop-Location
} else {
    if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
    git clone --depth 1 $UpstreamRepo $BuildDir
    if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to clone upstream repo" }
    Write-Ok "Cloned upstream repo"
}

# --- Apply buildUrl patch ---
$TargetFile = "$BuildDir\kun\src\adapters\model\deepseek-compat-model-client.ts"
if (-not (Test-Path $TargetFile)) {
    $TargetFile = "$BuildDir\kun\src\adapters\model\deepseek-compat-model-client.js"
}

if (Test-Path $TargetFile) {
    Write-Info "Applying buildUrl versioned-path fix to Kun runtime..."

    $content = Get-Content $TargetFile -Raw
    if ($content -match "versioned") {
        Write-Ok "buildUrl patch already applied, skipping"
    } else {
        # Use the pre-built patched file if available
        $patchedFile = "$PatchDir\patches\deepseek-compat-model-client.patched.js"
        if (Test-Path $patchedFile) {
            Write-Info "Using pre-built patched file..."
            $backupFile = "$TargetFile.bak"
            Copy-Item $TargetFile $backupFile -Force
            Copy-Item $patchedFile $TargetFile -Force
            Write-Ok "buildUrl patch applied successfully"
        } else {
            # Apply inline patch via regex
            $backupFile = "$TargetFile.bak"
            Copy-Item $TargetFile $backupFile -Force

            $patchPattern = @'
buildUrl\(path\) \{
\s*const base = this\.config\.baseUrl\.replace\(/\\\/\+\$/, ['"]'['"]?\);
\s*return `\$\{base\}\$\{path\}`;
\s*\}
'@
            $patchReplacement = @'
buildUrl(path) {
        const base = this.config.baseUrl.replace(/\/+$/, "");
        if (path === "/v1/chat/completions") {
            if (base.endsWith("/chat/completions")) return base;
            const versioned = /\/v\d+$/.test(base);
            if (versioned) return `${base}/chat/completions`;
        }
        return `${base}${path}`;
    }
'@
            $content = $content -replace $patchPattern, $patchReplacement
            Set-Content $TargetFile $content -NoNewline

            $verify = Get-Content $TargetFile -Raw
            if ($verify -match "versioned") {
                Write-Ok "buildUrl patch applied successfully"
            } else {
                Write-Warn "Automatic patch may have failed. Restoring backup."
                Copy-Item $backupFile $TargetFile -Force
                Write-Warn "Please apply patches/buildUrl-fix.patch manually"
            }
        }
    }
} else {
    Write-Warn "Cannot find deepseek-compat-model-client source. Skipping buildUrl patch."
    Write-Warn "You may need to apply it manually. See patches/buildUrl-fix.patch"
}

# --- Add GLM model profiles to Kun config ---
$KunConfig = "$BuildDir\kun\config.json"
if (Test-Path $KunConfig) {
    Write-Info "Adding GLM model profiles to Kun config..."

    $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $pythonCmd) { $pythonCmd = Get-Command python -ErrorAction SilentlyContinue }

    if ($pythonCmd) {
        & $pythonCmd "$PatchDir\scripts\patch-kun-config.py" $KunConfig "$PatchDir\config\kun-config.json"
    } else {
        Write-Warn "Python not found, copying full X Edition Kun config"
        Copy-Item "$PatchDir\config\kun-config.json" $KunConfig -Force
    }
    Write-Ok "Kun config updated with GLM profiles"
} else {
    Write-Warn "Kun config.json not found at $KunConfig"
}

# --- Build ---
if ($SkipBuild) {
    Write-Info "Skipping build (-SkipBuild flag)"
    Write-Ok "Patches applied to source at $BuildDir"
} else {
    Write-Info "Installing dependencies..."
    Push-Location $BuildDir
    npm install --no-fund --no-audit
    if ($LASTEXITCODE -ne 0) { Write-Fail "npm install failed" }

    Write-Info "Building DeepSeek GUI..."
    npm run build
    if ($LASTEXITCODE -ne 0) { Write-Fail "npm run build failed" }

    Write-Info "Creating Windows installer..."
    npm run dist:win
    if ($LASTEXITCODE -ne 0) { Write-Fail "npm run dist:win failed" }

    Pop-Location
    Write-Ok "Build complete!"
}

# --- Summary ---
Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "  DeepSeek GUI X Edition - Ready!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Upstream source:  $BuildDir"
Write-Host "  Patches applied:  buildUrl fix, GLM model profiles"
Write-Host ""
Write-Host "  Find your built installer in:"
Write-Host "    $BuildDir\dist\DeepSeek-GUI*.exe"
Write-Host ""
Write-Host "  To configure GLM models, run the settings patcher:"
Write-Host "    python $PatchDir\scripts\install.py --gui-settings %APPDATA%\DeepSeek GUI\deepseek-gui-settings.json"
Write-Host ""
