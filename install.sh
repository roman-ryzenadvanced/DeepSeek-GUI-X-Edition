#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  DeepSeek GUI X Edition - Source Installer
#  Platforms: Linux, macOS
#  Clones upstream DeepSeek-GUI, applies X Edition patches,
#  builds from source, and produces a runnable application.
#
#  Usage:
#    curl -sL https://raw.githubusercontent.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition/main/install.sh | bash
#    -- or --
#    git clone https://github.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition.git
#    cd DeepSeek-GUI-X-Edition
#    bash install.sh
#
#  Flags:
#    --skip-build      Skip npm build (apply patches only to existing clone)
#    --build-dir DIR   Custom build directory (default: /tmp/deepseek-gui-build)
#    --no-color        Disable colored output
# ============================================================

# --- Config ---
UPSTREAM_REPO="https://github.com/XingYu-Zhong/DeepSeek-GUI.git"
DEFAULT_BUILD_DIR="/tmp/deepseek-gui-build"
SKIP_BUILD=false
BUILD_DIR="$DEFAULT_BUILD_DIR"
USE_COLOR=true

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
        --skip-build)    SKIP_BUILD=true ;;
        --build-dir)     shift; BUILD_DIR="${1:-$DEFAULT_BUILD_DIR}" ;;
        --no-color)      USE_COLOR=false ;;
        --help|-h)
            head -20 "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
    esac
done

# --- Detect platform ---
detect_platform() {
    case "$(uname -s)" in
        Linux*)     PLATFORM="linux"  ;;
        Darwin*)    PLATFORM="macos"  ;;
        *)          fail "Unsupported platform: $(uname -s). Use install.ps1 for Windows." ;;
    esac
    info "Detected platform: $PLATFORM"
}

# --- Check prerequisites ---
check_prerequisites() {
    info "Checking prerequisites..."

    command -v node >/dev/null 2>&1 || fail "Node.js is not installed. Install Node.js 20+ first."
    command -v npm >/dev/null 2>&1  || fail "npm is not installed."

    local node_version
    node_version=$(node -v | sed 's/v//' | cut -d. -f1)
    if [ "$node_version" -lt 20 ]; then
        fail "Node.js 20+ required. Found: $(node -v)"
    fi
    ok "Node.js $(node -v)"
    ok "npm $(npm -v)"
}

# --- Locate X Edition patches ---
find_patch_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # If running from the X Edition repo directly
    if [ -d "$script_dir/patches" ] && [ -d "$script_dir/config" ]; then
        PATCH_DIR="$script_dir"
        return
    fi

    # If patches are in CWD
    if [ -d "./patches" ] && [ -d "./config" ]; then
        PATCH_DIR="."
        return
    fi

    fail "Cannot find X Edition patches directory. Clone the repo first:
  git clone https://github.com/roman-ryzenadvanced/DeepSeek-GUI-X-Edition.git
  cd DeepSeek-GUI-X-Edition && bash install.sh"
}

# --- Clone or update upstream ---
clone_upstream() {
    info "Cloning upstream DeepSeek-GUI into $BUILD_DIR..."

    if [ -d "$BUILD_DIR/.git" ]; then
        info "Existing clone found, pulling latest..."
        git -C "$BUILD_DIR" pull --ff-only || warn "Git pull failed, using existing clone"
    else
        rm -rf "$BUILD_DIR"
        git clone --depth 1 "$UPSTREAM_REPO" "$BUILD_DIR" || fail "Failed to clone upstream repo"
        ok "Cloned upstream repo"
    fi
}

# --- Apply buildUrl patch ---
apply_buildurl_patch() {
    local target_file="$BUILD_DIR/kun/src/adapters/model/deepseek-compat-model-client.ts"

    if [ ! -f "$target_file" ]; then
        # Try JS variant
        target_file="$BUILD_DIR/kun/src/adapters/model/deepseek-compat-model-client.js"
    fi

    if [ ! -f "$target_file" ]; then
        warn "Cannot find deepseek-compat-model-client source. Skipping buildUrl patch."
        warn "You may need to apply it manually. See patches/buildUrl-fix.patch"
        return
    fi

    info "Applying buildUrl versioned-path fix to Kun runtime..."

    # Check if already patched
    if grep -q "versioned" "$target_file" 2>/dev/null; then
        ok "buildUrl patch already applied, skipping"
        return
    fi

    # Apply the patch using sed (cross-platform friendly)
    # The original buildUrl method looks like:
    #   buildUrl(path) {
    #       const base = this.config.baseUrl.replace(/\/+$/, '');
    #       return `${base}${path}`;
    #   }
    # We need to insert the versioned URL detection logic

    local backup="${target_file}.bak"
    cp "$target_file" "$backup"

    # Use the pre-built patched file if available
    local patched="$PATCH_DIR/patches/deepseek-compat-model-client.patched.js"
    if [ -f "$patched" ]; then
        info "Using pre-built patched file..."
        # Determine the output extension
        local ext="${target_file##*.}"
        if [ "$ext" = "ts" ]; then
            # For TypeScript sources, we apply the diff logic inline
            sed -i 's|buildUrl(path) {|buildUrl(path) {\n        const base = this.config.baseUrl.replace(/\\/+$/, "");\n        if (path === "/v1/chat/completions") {\n            if (base.endsWith("/chat/completions")) return base;\n            const versioned = /\\\\/v\\d+$/.test(base);\n            if (versioned) return `${base}/chat/completions`;\n        }|' "$target_file" 2>/dev/null
        else
            cp "$patched" "$target_file"
        fi
    else
        # Apply inline patch
        sed -i '/buildUrl(path) {/,/return `${base}${path}`;/c\    buildUrl(path) {\
        const base = this.config.baseUrl.replace(/\\/+$/, "");\
        if (path === "/v1/chat/completions") {\
            if (base.endsWith("/chat/completions")) return base;\
            const versioned = /\\\\/v\\d+$/.test(base);\
            if (versioned) return `${base}/chat/completions`;\
        }\
        return `${base}${path}`;\
    }' "$target_file"
    fi

    if grep -q "versioned" "$target_file" 2>/dev/null; then
        ok "buildUrl patch applied successfully"
    else
        warn "Automatic patch may have failed. Restoring backup."
        cp "$backup" "$target_file"
        warn "Please apply patches/buildUrl-fix.patch manually"
    fi
}

# --- Add GLM model profiles to Kun config ---
patch_kun_config() {
    local kun_config="$BUILD_DIR/kun/config.json"

    if [ ! -f "$kun_config" ]; then
        warn "Kun config.json not found at $kun_config"
        return
    fi

    info "Adding GLM model profiles to Kun config..."

    # Use Python for reliable JSON merging if available
    if command -v python3 >/dev/null 2>&1; then
        python3 "$PATCH_DIR/scripts/patch-kun-config.py" "$kun_config" "$PATCH_DIR/config/kun-config.json"
    else
        # Fallback: copy the full X Edition config
        warn "python3 not found, copying full X Edition Kun config"
        cp "$PATCH_DIR/config/kun-config.json" "$kun_config"
    fi

    ok "Kun config updated with GLM profiles"
}

# --- Build the application ---
build_app() {
    info "Installing dependencies..."
    cd "$BUILD_DIR"
    npm install --no-fund --no-audit

    info "Building DeepSeek GUI..."
    npm run build

    case "$PLATFORM" in
        linux)  npm run dist:linux ;;
        macos)  npm run dist:mac ;;
    esac

    ok "Build complete!"
}

# --- Summary ---
print_summary() {
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  DeepSeek GUI X Edition - Ready!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo "  Upstream source:  $BUILD_DIR"
    echo "  Patches applied:  buildUrl fix, GLM model profiles"
    echo ""
    case "$PLATFORM" in
        linux)
            echo "  Find your built AppImage in:"
            echo "    $BUILD_DIR/dist/DeepSeek-GUI*.AppImage"
            echo ""
            echo "  Run it:"
            echo "    chmod +x $BUILD_DIR/dist/DeepSeek-GUI*.AppImage"
            echo "    $BUILD_DIR/dist/DeepSeek-GUI*.AppImage"
            ;;
        macos)
            echo "  Find your built app in:"
            echo "    $BUILD_DIR/dist/DeepSeek GUI*.dmg"
            echo ""
            echo "  Run it:"
            echo "    open \"$BUILD_DIR/dist/DeepSeek GUI*.dmg\""
            ;;
    esac
    echo ""
    echo "  To configure GLM models, run the settings patcher:"
    echo "    python3 $PATCH_DIR/scripts/install.py --gui-settings ~/.config/deepseek-gui/deepseek-gui-settings.json"
    echo ""
}

# --- Main ---
main() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}  DeepSeek GUI X Edition Installer${NC}"
    echo -e "${BLUE}  (Build from Source)${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""

    detect_platform
    check_prerequisites
    find_patch_dir
    clone_upstream

    # Apply X Edition patches
    apply_buildurl_patch
    patch_kun_config

    if $SKIP_BUILD; then
        info "Skipping build (--skip-build flag)"
        ok "Patches applied to source at $BUILD_DIR"
    else
        build_app
    fi

    print_summary
}

main "$@"
