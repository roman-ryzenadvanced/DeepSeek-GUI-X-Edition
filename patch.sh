#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  DeepSeek GUI X Edition - Patch Existing Installation
#  Platforms: Linux, macOS
#
#  For users who already have DeepSeek GUI installed and want
#  to add multi-provider support WITHOUT rebuilding from source.
#
#  This script:
#    1. Detects your existing DeepSeek GUI installation
#    2. Copies the pre-patched Kun runtime to ~/.deepseekgui/kun-patched/
#    3. Patches GUI settings with binaryPath override
#    4. Adds GLM model profiles to Kun config
#    5. Installs the dsgui launcher + shell alias
#
#  Usage:
#    git clone https://github.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition.git
#    cd DeepSeek-GUI-X-Edition
#    bash patch.sh
#
#  Flags:
#    --kun-dist DIR    Path to pre-built kun-dist (default: ./kun-dist)
#    --kun-modules DIR Path to kun node_modules (default: ./kun-node_modules)
#    --no-color        Disable colored output
#    --uninstall       Remove patches and launcher
# ============================================================

# --- Config ---
KUN_DIST_DIR=""
KUN_MODULES_DIR=""
USE_COLOR=true
UNINSTALL=false

# --- Colors ---
if $USE_COLOR; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# --- Parse arguments ---
for arg in "$@"; do
    case "$arg" in
        --kun-dist)      shift; KUN_DIST_DIR="${1:-}" ;;
        --kun-modules)   shift; KUN_MODULES_DIR="${1:-}" ;;
        --no-color)      USE_COLOR=false ;;
        --uninstall)     UNINSTALL=true ;;
        --help|-h)
            head -25 "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
    esac
done

# --- Paths ---
HOME_DIR="$(cd ~ && pwd)"
XEDITION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUN_PATCHED_DIR="$HOME_DIR/.deepseekgui/kun-patched"

# Platform-specific paths
case "$(uname -s)" in
    Linux*)
        PLATFORM="linux"
        GUI_SETTINGS_DIR="$HOME_DIR/.config/deepseek-gui"
        GUI_SETTINGS_FILE="$GUI_SETTINGS_DIR/deepseek-gui-settings.json"
        ;;
    Darwin*)
        PLATFORM="macos"
        GUI_SETTINGS_DIR="$HOME_DIR/Library/Application Support/deepseek-gui"
        GUI_SETTINGS_FILE="$GUI_SETTINGS_DIR/deepseek-gui-settings.json"
        ;;
    *)
        fail "Unsupported platform: $(uname -s). Use patch.ps1 for Windows."
        ;;
esac

KUN_CONFIG_DIR="$HOME_DIR/.deepseekgui/kun"
KUN_CONFIG_FILE="$KUN_CONFIG_DIR/config.json"
LAUNCHER_DIR="$HOME_DIR/.deepseekgui"
LAUNCHER_FILE="$LAUNCHER_DIR/dsgui-launcher.py"
PROVIDERS_FILE="$LAUNCHER_DIR/providers.json"

# --- Locate pre-built Kun runtime ---
find_kun_dist() {
    if [ -n "$KUN_DIST_DIR" ]; then
        [ -d "$KUN_DIST_DIR" ] || fail "Custom kun-dist not found: $KUN_DIST_DIR"
        return
    fi

    # Check X Edition repo
    if [ -d "$XEDITION_DIR/kun-dist" ]; then
        KUN_DIST_DIR="$XEDITION_DIR/kun-dist"
        return
    fi

    fail "Pre-built Kun runtime not found.

Clone the X Edition repo (with kun-dist included) first:
  git clone https://github.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition.git
  cd DeepSeek-GUI-X-Edition
  bash patch.sh

Or specify a custom path:
  bash patch.sh --kun-dist /path/to/kun-dist"
}

find_kun_modules() {
    if [ -n "$KUN_MODULES_DIR" ]; then
        [ -d "$KUN_MODULES_DIR" ] || fail "Custom kun-node_modules not found: $KUN_MODULES_DIR"
        return
    fi

    # Check X Edition repo
    if [ -d "$XEDITION_DIR/kun-node_modules" ]; then
        KUN_MODULES_DIR="$XEDITION_DIR/kun-node_modules"
        return
    fi

    warn "kun-node_modules not found in X Edition repo."
    warn "The patched runtime may need 'npm install' in kun-patched/ to work."
}

# --- Detect existing DeepSeek GUI installation ---
detect_installation() {
    info "Looking for existing DeepSeek GUI installation..."

    local found=false

    case "$PLATFORM" in
        linux)
            # Check AppImage locations
            for candidate in \
                "$HOME_DIR/Applications/DeepSeek-GUI.AppImage" \
                "$HOME_DIR/Desktop/DeepSeek-GUI.AppImage" \
                "$HOME_DIR/Downloads/DeepSeek-GUI.AppImage" \
                "/opt/DeepSeek-GUI/DeepSeek-GUI" \
                "/usr/bin/deepseek-gui" \
                "$HOME_DIR/.local/bin/deepseek-gui"; do
                if [ -f "$candidate" ]; then
                    ok "Found: $candidate"
                    found=true
                fi
            done
            ;;
        macos)
            for candidate in \
                "$HOME_DIR/Applications/DeepSeek GUI.app" \
                "/Applications/DeepSeek GUI.app"; do
                if [ -d "$candidate" ]; then
                    ok "Found: $candidate"
                    found=true
                fi
            done
            ;;
    esac

    if ! $found; then
        warn "Could not auto-detect a DeepSeek GUI installation."
        warn "If you have it installed elsewhere, the launcher will ask for the path."
        warn "You can also pass it later via: dsgui --quick <provider>"
    fi

    # Check for existing GUI settings (means the app has been run at least once)
    if [ -f "$GUI_SETTINGS_FILE" ]; then
        ok "GUI settings found: $GUI_SETTINGS_FILE"
    else
        warn "GUI settings not found at $GUI_SETTINGS_FILE"
        warn "Make sure you've launched DeepSeek GUI at least once."
        warn "The patch will create the directory, but you'll need to run the app once first."
    fi
}

# --- Copy patched Kun runtime ---
install_kun_runtime() {
    info "Installing patched Kun runtime to $KUN_PATCHED_DIR ..."

    # Create target directory
    mkdir -p "$KUN_PATCHED_DIR"

    # Copy the dist directory
    if [ -d "$KUN_PATCHED_DIR/dist" ]; then
        info "Existing patched runtime found, updating..."
        rm -rf "$KUN_PATCHED_DIR/dist"
    fi

    cp -r "$KUN_DIST_DIR" "$KUN_PATCHED_DIR/dist"
    ok "Copied kun-dist/ -> $KUN_PATCHED_DIR/dist"

    # Copy node_modules if available
    if [ -n "$KUN_MODULES_DIR" ] && [ -d "$KUN_MODULES_DIR" ]; then
        if [ -d "$KUN_PATCHED_DIR/node_modules" ]; then
            rm -rf "$KUN_PATCHED_DIR/node_modules"
        fi
        cp -r "$KUN_MODULES_DIR" "$KUN_PATCHED_DIR/node_modules"
        ok "Copied kun-node_modules/ -> $KUN_PATCHED_DIR/node_modules"
    fi

    # Verify the patched file
    local patched_js="$KUN_PATCHED_DIR/dist/adapters/model/deepseek-compat-model-client.js"
    if [ -f "$patched_js" ] && grep -q "versioned" "$patched_js"; then
        ok "Verified: buildUrl patch is present in patched runtime"
    elif [ -f "$patched_js" ]; then
        warn "buildUrl patch not detected in runtime — applying now..."
        apply_inline_patch "$patched_js"
    else
        warn "Could not verify patch status (file not found at expected path)"
    fi
}

# --- Apply inline buildUrl patch (fallback) ---
apply_inline_patch() {
    local target="$1"
    local backup="${target}.bak"

    cp "$target" "$backup"

    # The original buildUrl is:
    #   buildUrl(path) {
    #       const base = this.config.baseUrl.replace(/\/+$/, '');
    #       return `${base}${path}`;
    #   }
    # Replace with versioned-URL-aware version

    local patched="$XEDITION_DIR/patches/deepseek-compat-model-client.patched.js"
    if [ -f "$patched" ]; then
        cp "$patched" "$target"
    else
        # Inline sed patch
        sed -i '/buildUrl(path) {/,/return `${base}${path}`;/c\    buildUrl(path) {\
        const base = this.config.baseUrl.replace(/\\/+$/, "");\
        if (path === "/v1/chat/completions") {\
            if (base.endsWith("/chat/completions")) return base;\
            const versioned = /\\\\/v\\d+$/.test(base);\
            if (versioned) return `${base}/chat/completions`;\
        }\
        return `${base}${path}`;\
    }' "$target"
    fi

    if grep -q "versioned" "$target" 2>/dev/null; then
        ok "buildUrl patch applied successfully"
    else
        warn "Automatic patch failed. Restoring backup."
        cp "$backup" "$target"
        warn "Apply patches/buildUrl-fix.patch manually to: $target"
    fi
}

# --- Patch GUI settings ---
patch_gui_settings() {
    info "Patching GUI settings..."

    if [ ! -f "$GUI_SETTINGS_FILE" ]; then
        # Create directory and minimal settings
        mkdir -p "$GUI_SETTINGS_DIR"
        warn "No existing GUI settings found. Creating minimal config..."
        cat > "$GUI_SETTINGS_FILE" << 'SETTINGS_EOF'
{
  "provider": {
    "baseUrl": "",
    "apiKey": "YOUR_API_KEY_HERE",
    "providers": []
  },
  "agents": {
    "kun": {
      "model": "glm-5.1"
    }
  }
}
SETTINGS_EOF
        warn "Created minimal config at $GUI_SETTINGS_FILE"
        warn "Use 'dsgui --add' to configure your provider after installation."
    fi

    # Use Python patcher if available
    if command -v python3 >/dev/null 2>&1; then
        python3 "$XEDITION_DIR/scripts/install.py" \
            --gui-settings "$GUI_SETTINGS_FILE" \
            --binary-path "$KUN_PATCHED_DIR"
        ok "GUI settings patched (python3)"
    else
        # Fallback: use jq or manual sed
        if command -v jq >/dev/null 2>&1; then
            warn "python3 not found, using jq for basic patching..."
            jq --arg bp "$KUN_PATCHED_DIR" '
                if .agents == null then .agents = {} else . end |
                if .agents.kun == null then .agents.kun = {} else . end |
                .agents.kun.binaryPath = $bp
            ' "$GUI_SETTINGS_FILE" > "${GUI_SETTINGS_FILE}.tmp" \
                && mv "${GUI_SETTINGS_FILE}.tmp" "$GUI_SETTINGS_FILE"
            ok "GUI settings patched (jq) — binaryPath set to $KUN_PATCHED_DIR"
        else
            warn "Neither python3 nor jq found. GUI settings patching skipped."
            warn "Manually set binaryPath to '$KUN_PATCHED_DIR' in:"
            warn "  $GUI_SETTINGS_FILE"
        fi
    fi
}

# --- Patch Kun config ---
patch_kun_config() {
    info "Adding GLM model profiles to Kun config..."

    mkdir -p "$KUN_CONFIG_DIR"

    if command -v python3 >/dev/null 2>&1; then
        python3 "$XEDITION_DIR/scripts/patch-kun-config.py" \
            "$KUN_CONFIG_FILE" "$XEDITION_DIR/config/kun-config.json" 2>/dev/null || {
            warn "Python patcher failed, copying full config..."
            cp "$XEDITION_DIR/config/kun-config.json" "$KUN_CONFIG_FILE"
        }
        ok "Kun config updated with GLM profiles"
    else
        if [ ! -f "$KUN_CONFIG_FILE" ]; then
            cp "$XEDITION_DIR/config/kun-config.json" "$KUN_CONFIG_FILE"
            ok "Kun config installed (full copy)"
        else
            warn "python3 not found. Kun config already exists — skipping merge."
            warn "Manually add GLM profiles from: $XEDITION_DIR/config/kun-config.json"
        fi
    fi
}

# --- Install launcher ---
install_launcher() {
    info "Installing dsgui launcher..."

    mkdir -p "$LAUNCHER_DIR"

    # Copy launcher script
    if [ -f "$XEDITION_DIR/launcher/dsgui-launcher.py" ]; then
        cp "$XEDITION_DIR/launcher/dsgui-launcher.py" "$LAUNCHER_FILE"
        chmod +x "$LAUNCHER_FILE"
        ok "Launcher installed: $LAUNCHER_FILE"
    else
        fail "Launcher not found: $XEDITION_DIR/launcher/dsgui-launcher.py"
    fi

    # Copy providers example if no config exists
    if [ ! -f "$PROVIDERS_FILE" ]; then
        if [ -f "$XEDITION_DIR/launcher/providers.json.example" ]; then
            cp "$XEDITION_DIR/launcher/providers.json.example" "$PROVIDERS_FILE"
            ok "Providers config created: $PROVIDERS_FILE"
            ok "Edit this file or use 'dsgui --add' to add providers."
        fi
    else
        ok "Providers config already exists: $PROVIDERS_FILE (not overwritten)"
    fi
}

# --- Add shell alias ---
add_shell_alias() {
    info "Adding 'dsgui' alias to your shell config..."

    local alias_line="alias dsgui='python3 $LAUNCHER_FILE'"
    local alias_added=false

    # Detect active shell config files
    local shell_configs=()
    [ -f "$HOME_DIR/.bashrc" ] && shell_configs+=("$HOME_DIR/.bashrc")
    [ -f "$HOME_DIR/.zshrc" ] && shell_configs+=("$HOME_DIR/.zshrc")
    [ -f "$HOME_DIR/.bash_profile" ] && shell_configs+=("$HOME_DIR/.bash_profile")

    for config in "${shell_configs[@]}"; do
        if grep -q "alias dsgui=" "$config" 2>/dev/null; then
            # Update existing alias
            sed -i "s|alias dsgui=.*|${alias_line}|" "$config"
            ok "Updated dsgui alias in $config"
            alias_added=true
            break
        fi
    done

    if ! $alias_added; then
        # Add to the first available config file
        if [ ${#shell_configs[@]} -gt 0 ]; then
            echo "" >> "${shell_configs[0]}"
            echo "# DeepSeek GUI X Edition launcher" >> "${shell_configs[0]}"
            echo "$alias_line" >> "${shell_configs[0]}"
            ok "Added dsgui alias to ${shell_configs[0]}"
        else
            warn "No shell config file found (.bashrc, .zshrc, .bash_profile)"
            warn "Add this alias manually:"
            warn "  $alias_line"
        fi
    fi
}

# --- Uninstall ---
do_uninstall() {
    echo ""
    echo -e "${YELLOW}Uninstalling DeepSeek GUI X Edition patches...${NC}"
    echo ""

    # Remove patched Kun runtime
    if [ -d "$KUN_PATCHED_DIR" ]; then
        rm -rf "$KUN_PATCHED_DIR"
        ok "Removed $KUN_PATCHED_DIR"
    else
        warn "No patched runtime found at $KUN_PATCHED_DIR"
    fi

    # Remove launcher
    if [ -f "$LAUNCHER_FILE" ]; then
        rm -f "$LAUNCHER_FILE"
        ok "Removed $LAUNCHER_FILE"
    fi

    # Remove shell alias
    for config in "$HOME_DIR/.bashrc" "$HOME_DIR/.zshrc" "$HOME_DIR/.bash_profile"; do
        if [ -f "$config" ]; then
            if grep -q "alias dsgui=" "$config" 2>/dev/null; then
                sed -i '/alias dsgui=/d' "$config"
                sed -i '/# DeepSeek GUI X Edition launcher/d' "$config"
                ok "Removed dsgui alias from $config"
            fi
        fi
    done

    # Remove binaryPath from GUI settings
    if [ -f "$GUI_SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
        jq 'del(.agents.kun.binaryPath)' "$GUI_SETTINGS_FILE" > "${GUI_SETTINGS_FILE}.tmp" \
            && mv "${GUI_SETTINGS_FILE}.tmp" "$GUI_SETTINGS_FILE"
        ok "Removed binaryPath from GUI settings"
    fi

    echo ""
    ok "Uninstall complete. Your DeepSeek GUI installation is restored to original."
    echo ""
    exit 0
}

# --- Print summary ---
print_summary() {
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  DeepSeek GUI X Edition - Patched!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo "  Patched Kun runtime:  $KUN_PATCHED_DIR"
    echo "  Launcher:             $LAUNCHER_FILE"
    echo "  Providers config:     $PROVIDERS_FILE"
    echo "  GUI settings:         $GUI_SETTINGS_FILE"
    echo "  Kun config:           $KUN_CONFIG_FILE"
    echo ""
    echo -e "  ${GREEN}Next steps:${NC}"
    echo ""
    echo "    1. Source your shell config (or open a new terminal):"
    echo "       source ~/.bashrc   # or ~/.zshrc"
    echo ""
    echo "    2. Add your AI provider:"
    echo "       dsgui --add"
    echo ""
    echo "    3. Launch with:"
    echo "       dsgui"
    echo ""
    echo -e "  ${YELLOW}To remove patches later:${NC}"
    echo "       bash $XEDITION_DIR/patch.sh --uninstall"
    echo ""
}

# --- Main ---
main() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}  DeepSeek GUI X Edition${NC}"
    echo -e "${BLUE}  Patch Existing Installation${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""

    if $UNINSTALL; then
        do_uninstall
    fi

    info "Platform: $PLATFORM"
    info "Home:     $HOME_DIR"

    find_kun_dist
    find_kun_modules
    detect_installation

    echo ""
    echo -e "${BLUE}--- Installing patches ---${NC}"
    echo ""

    install_kun_runtime
    patch_gui_settings
    patch_kun_config
    install_launcher
    add_shell_alias

    print_summary
}

main "$@"
