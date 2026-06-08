#Requires -Version 5.1
<#
.SYNOPSIS
    DeepSeek GUI X Edition - Patch Existing Installation (Windows)

.DESCRIPTION
    For users who already have DeepSeek GUI installed and want to add
    multi-provider support WITHOUT rebuilding from source.

    This script:
      1. Detects your existing DeepSeek GUI installation
      2. Copies the pre-patched Kun runtime to ~/.deepseekgui/kun-patched/
      3. Patches GUI settings with binaryPath override
      4. Adds GLM model profiles to Kun config
      5. Installs the dsgui launcher

.PARAMETER KunDistDir
    Path to pre-built kun-dist directory

.PARAMETER KunModulesDir
    Path to kun node_modules directory

.PARAMETER Uninstall
    Remove patches and launcher

.EXAMPLE
    .\patch.ps1
    .\patch.ps1 -KunDistDir C:\path\to\kun-dist
    .\patch.ps1 -Uninstall

.NOTES
    Requires: Python 3 (recommended, for config patching)
#>

param(
    [string]$KunDistDir = "",
    [string]$KunModulesDir = "",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# --- Helpers ---
function Write-Info  { Write-Host "[INFO]  " -ForegroundColor Blue -NoNewline; Write-Host @args }
function Write-Ok    { Write-Host "[OK]    " -ForegroundColor Green -NoNewline; Write-Host @args }
function Write-Warn  { Write-Host "[WARN]  " -ForegroundColor Yellow -NoNewline; Write-Host @args }
function Write-Fail  { Write-Host "[FAIL]  " -ForegroundColor Red -NoNewline; Write-Host @args; exit 1 }

# --- Paths ---
$HomeDir = $env:USERPROFILE
$XEDitionDir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
$KunPatchedDir = Join-Path $HomeDir ".deepseekgui\kun-patched"
$GuiSettingsDir = Join-Path $env:APPDATA "DeepSeek GUI"
$GuiSettingsFile = Join-Path $GuiSettingsDir "deepseek-gui-settings.json"
$KunConfigDir = Join-Path $HomeDir ".deepseekgui\kun"
$KunConfigFile = Join-Path $KunConfigDir "config.json"
$LauncherDir = Join-Path $HomeDir ".deepseekgui"
$LauncherFile = Join-Path $LauncherDir "dsgui-launcher.py"
$ProvidersFile = Join-Path $LauncherDir "providers.json"

# --- Banner ---
Write-Host ""
Write-Host "=========================================" -ForegroundColor Blue
Write-Host "  DeepSeek GUI X Edition" -ForegroundColor Blue
Write-Host "  Patch Existing Installation" -ForegroundColor Blue
Write-Host "=========================================" -ForegroundColor Blue
Write-Host ""

# --- Uninstall ---
if ($Uninstall) {
    Write-Host "Uninstalling DeepSeek GUI X Edition patches..." -ForegroundColor Yellow
    Write-Host ""

    if (Test-Path $KunPatchedDir) {
        Remove-Item -Recurse -Force $KunPatchedDir
        Write-Ok "Removed $KunPatchedDir"
    }

    if (Test-Path $LauncherFile) {
        Remove-Item -Force $LauncherFile
        Write-Ok "Removed $LauncherFile"
    }

    Write-Host ""
    Write-Ok "Uninstall complete. Your DeepSeek GUI installation is restored to original."
    Write-Host ""
    exit 0
}

# --- Locate pre-built Kun runtime ---
if ($KunDistDir) {
    if (-not (Test-Path $KunDistDir)) { Write-Fail "Custom kun-dist not found: $KunDistDir" }
} else {
    $RepoKunDist = Join-Path $XEDitionDir "kun-dist"
    if (Test-Path $RepoKunDist) {
        $KunDistDir = $RepoKunDist
    } else {
        Write-Fail @"
Pre-built Kun runtime not found.

Clone the X Edition repo (with kun-dist included) first:
  git clone https://github.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition.git
  cd DeepSeek-GUI-X-Edition
  .\patch.ps1

Or specify a custom path:
  .\patch.ps1 -KunDistDir C:\path\to\kun-dist
"@
    }
}

# Locate node_modules
if (-not $KunModulesDir) {
    $RepoKunModules = Join-Path $XEDitionDir "kun-node_modules"
    if (Test-Path $RepoKunModules) {
        $KunModulesDir = $RepoKunModules
    }
}

# --- Detect existing installation ---
Write-Info "Looking for existing DeepSeek GUI installation..."

$Found = $false
$candidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\DeepSeek GUI\DeepSeek-GUI.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "DeepSeek GUI\DeepSeek-GUI.exe"),
    (Join-Path ${env:ProgramFiles} "DeepSeek GUI\DeepSeek-GUI.exe"),
    (Join-Path $HomeDir "Desktop\DeepSeek-GUI.exe"),
    (Join-Path $HomeDir "Downloads\DeepSeek-GUI.exe")
)

foreach ($c in $candidates) {
    if (Test-Path $c) {
        Write-Ok "Found: $c"
        $Found = $true
    }
}

if (-not $Found) {
    Write-Warn "Could not auto-detect a DeepSeek GUI installation."
    Write-Warn "The launcher will ask for the path when you run 'dsgui'."
}

if (Test-Path $GuiSettingsFile) {
    Write-Ok "GUI settings found: $GuiSettingsFile"
} else {
    Write-Warn "GUI settings not found at $GuiSettingsFile"
    Write-Warn "Make sure you've launched DeepSeek GUI at least once."
}

# --- Copy patched Kun runtime ---
Write-Host ""
Write-Host "--- Installing patches ---" -ForegroundColor Blue
Write-Host ""

Write-Info "Installing patched Kun runtime to $KunPatchedDir ..."

New-Item -ItemType Directory -Force -Path $KunPatchedDir | Out-Null

$TargetDist = Join-Path $KunPatchedDir "dist"
if (Test-Path $TargetDist) {
    Write-Info "Existing patched runtime found, updating..."
    Remove-Item -Recurse -Force $TargetDist
}
Copy-Item -Recurse $KunDistDir $TargetDist
Write-Ok "Copied kun-dist/ -> $TargetDist"

if ($KunModulesDir -and (Test-Path $KunModulesDir)) {
    $TargetModules = Join-Path $KunPatchedDir "node_modules"
    if (Test-Path $TargetModules) {
        Remove-Item -Recurse -Force $TargetModules
    }
    Copy-Item -Recurse $KunModulesDir $TargetModules
    Write-Ok "Copied kun-node_modules/ -> $TargetModules"
}

# Verify patch
$PatchedJs = Join-Path $TargetDist "adapters\model\deepseek-compat-model-client.js"
if ((Test-Path $PatchedJs) -and (Get-Content $PatchedJs -Raw) -match "versioned") {
    Write-Ok "Verified: buildUrl patch is present in patched runtime"
} elseif (Test-Path $PatchedJs) {
    Write-Warn "buildUrl patch not detected in runtime. Apply patches/buildUrl-fix.patch manually."
}

# --- Patch GUI settings ---
Write-Info "Patching GUI settings..."

if (-not (Test-Path $GuiSettingsFile)) {
    New-Item -ItemType Directory -Force -Path $GuiSettingsDir | Out-Null
    Write-Warn "No existing GUI settings found. Creating minimal config..."
    @{
        provider = @{
            baseUrl = ""
            apiKey = "YOUR_API_KEY_HERE"
            providers = @()
        }
        agents = @{
            kun = @{
                model = "glm-5.1"
            }
        }
    } | ConvertTo-Json -Depth 5 | Set-Content $GuiSettingsFile
    Write-Warn "Created minimal config. Use 'dsgui --add' to configure your provider."
}

$pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $pythonCmd) { $pythonCmd = Get-Command python -ErrorAction SilentlyContinue }

if ($pythonCmd) {
    & $pythonCmd "$XEDitionDir\scripts\install.py" --gui-settings $GuiSettingsFile --binary-path $KunPatchedDir
    Write-Ok "GUI settings patched"
} else {
    Write-Warn "Python not found. GUI settings patching skipped."
    Write-Warn "Manually set binaryPath to '$KunPatchedDir' in: $GuiSettingsFile"
}

# --- Patch Kun config ---
Write-Info "Adding GLM model profiles to Kun config..."

New-Item -ItemType Directory -Force -Path $KunConfigDir | Out-Null

if ($pythonCmd) {
    & $pythonCmd "$XEDitionDir\scripts\patch-kun-config.py" $KunConfigFile "$XEDitionDir\config\kun-config.json" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Python patcher failed, copying full config..."
        Copy-Item "$XEDitionDir\config\kun-config.json" $KunConfigFile -Force
    }
    Write-Ok "Kun config updated with GLM profiles"
} else {
    if (-not (Test-Path $KunConfigFile)) {
        Copy-Item "$XEDitionDir\config\kun-config.json" $KunConfigFile -Force
        Write-Ok "Kun config installed (full copy)"
    } else {
        Write-Warn "Python not found. Kun config already exists - skipping merge."
    }
}

# --- Install launcher ---
Write-Info "Installing dsgui launcher..."

New-Item -ItemType Directory -Force -Path $LauncherDir | Out-Null

$SourceLauncher = Join-Path $XEDitionDir "launcher\dsgui-launcher.py"
if (Test-Path $SourceLauncher) {
    Copy-Item $SourceLauncher $LauncherFile -Force
    Write-Ok "Launcher installed: $LauncherFile"
} else {
    Write-Fail "Launcher not found: $SourceLauncher"
}

if (-not (Test-Path $ProvidersFile)) {
    $ExampleProviders = Join-Path $XEDitionDir "launcher\providers.json.example"
    if (Test-Path $ExampleProviders) {
        Copy-Item $ExampleProviders $ProvidersFile -Force
        Write-Ok "Providers config created: $ProvidersFile"
    }
} else {
    Write-Ok "Providers config already exists: $ProvidersFile (not overwritten)"
}

# --- Summary ---
Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "  DeepSeek GUI X Edition - Patched!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Patched Kun runtime:  $KunPatchedDir"
Write-Host "  Launcher:             $LauncherFile"
Write-Host "  Providers config:     $ProvidersFile"
Write-Host "  GUI settings:         $GuiSettingsFile"
Write-Host "  Kun config:           $KunConfigFile"
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Green
Write-Host ""
Write-Host "    1. Add your AI provider:"
Write-Host "       python $LauncherFile --add"
Write-Host ""
Write-Host "    2. Launch with:"
Write-Host "       python $LauncherFile"
Write-Host ""
Write-Host "  To remove patches later:" -ForegroundColor Yellow
Write-Host "       .\patch.ps1 -Uninstall"
Write-Host ""
