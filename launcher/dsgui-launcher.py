#!/usr/bin/env python3
"""
DeepSeek GUI Launcher — Multi-Provider Terminal Wrapper

A portable CLI launcher for DeepSeek GUI that lets you add multiple
AI providers, select provider/model interactively, then launch the GUI
with the correct configuration.

Works on: Linux, macOS, WSL2

Usage:
  python3 dsgui-launcher.py                # Interactive launcher
  python3 dsgui-launcher.py --add          # Add a new provider
  python3 dsgui-launcher.py --remove       # Remove a provider
  python3 dsgui-launcher.py --list         # List providers & models
  python3 dsgui-launcher.py --quick zai    # Quick launch with provider
"""

import json
import os
import sys
import shutil
import subprocess
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).parent.resolve()
CONFIG_FILE = SCRIPT_DIR / "providers.json"

# Detect platform-specific paths
HOME = Path.home()
PLATFORM = sys.platform

if PLATFORM == "darwin":
    # macOS
    GUI_SETTINGS = HOME / "Library/Application Support/deepseek-gui/deepseek-gui-settings.json"
    KUN_CONFIG = HOME / ".deepseekgui/kun/config.json"
    KUN_PATCHED = HOME / ".deepseekgui/kun-patched"
    APPIMAGE_PATH = None  # macOS uses .app bundle
elif PLATFORM == "win32" or "microsoft" in os.uname().release.lower() if hasattr(os, 'uname') else False:
    # Windows / WSL2
    GUI_SETTINGS = HOME / ".config/deepseek-gui/deepseek-gui-settings.json"
    KUN_CONFIG = HOME / ".deepseekgui/kun/config.json"
    KUN_PATCHED = HOME / ".deepseekgui/kun-patched"
    APPIMAGE_PATH = None
else:
    # Linux
    GUI_SETTINGS = HOME / ".config/deepseek-gui/deepseek-gui-settings.json"
    KUN_CONFIG = HOME / ".deepseekgui/kun/config.json"
    KUN_PATCHED = HOME / ".deepseekgui/kun-patched"
    APPIMAGE_PATH = HOME / "Applications/DeepSeek-GUI.AppImage"

# Colors
C_RESET = "\033[0m"
C_BOLD = "\033[1m"
C_DIM = "\033[2m"
C_RED = "\033[31m"
C_GREEN = "\033[32m"
C_YELLOW = "\033[33m"
C_BLUE = "\033[34m"
C_CYAN = "\033[36m"
C_MAGENTA = "\033[35m"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def load_providers():
    if CONFIG_FILE.exists():
        with open(CONFIG_FILE) as f:
            return json.load(f)
    return {"providers": {}, "gui_executable": ""}

def save_providers(cfg):
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)

# ---------------------------------------------------------------------------
# Terminal helpers
# ---------------------------------------------------------------------------

def clear():
    os.system("cls" if PLATFORM == "win32" else "clear")

def print_banner():
    print()
    print(C_CYAN + "  ╔═══════════════════════════════════════════╗" + C_RESET)
    print(C_CYAN + "  ║" + C_BOLD + "    DeepSeek GUI — Multi-Provider Launcher    " + C_CYAN + "║" + C_RESET)
    print(C_CYAN + "  ╚═══════════════════════════════════════════╝" + C_RESET)
    print()

def print_provider(name, provider):
    base = provider.get("base_url", "?")
    models = provider.get("models", [])
    key = provider.get("api_key", "")
    key_display = key[:4] + "..." + key[-4:] if len(key) > 8 else key
    print("  {}{}{} [{}] {}".format(C_BOLD, name, C_RESET, key_display, base))
    if models:
        print("    Models: {}".format(", ".join(models[:5])), end="")
        if len(models) > 5:
            print(" ... +{} more".format(len(models) - 5), end="")
        print()

def pick_option(prompt, options, allow_back=True):
    """Display numbered options and return the selected index."""
    print()
    for i, opt in enumerate(options):
        label = opt if isinstance(opt, str) else opt.get("label", str(opt))
        print("  {}{}{}) {} {}".format(C_BOLD, i + 1, C_RESET, label, C_DIM if isinstance(opt, str) else opt.get("hint", "") + C_RESET))
    if allow_back:
        print("  {}{}{}) Back".format(C_BOLD, 0, C_RESET))
    print()
    while True:
        try:
            choice = input("  {}> {}".format(C_CYAN, C_RESET)).strip()
            if choice == "" and allow_back:
                return -1
            idx = int(choice) - 1
            if allow_back and idx == -1:
                return -1
            if 0 <= idx < len(options):
                return idx
            print("  {}Invalid choice. Try again.{}".format(C_RED, C_RESET))
        except (ValueError, EOFError):
            if allow_back:
                return -1
            print("  {}Invalid choice.{}".format(C_RED, C_RESET))

# ---------------------------------------------------------------------------
# Provider management
# ---------------------------------------------------------------------------

def discover_models(base_url, api_key):
    """Auto-discover models from an OpenAI-compatible /models endpoint."""
    import urllib.request
    import urllib.error
    url = base_url.rstrip("/") + "/models"
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = "Bearer {}".format(api_key)
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
            all_models = [m["id"] for m in data.get("data", [])]
            # Filter noise
            filtered = [m for m in all_models
                       if "-no-thinking" not in m
                       and ("-preview" not in m.lower() or "qwen3.6" in m)]
            return filtered, all_models
    except Exception as e:
        print("  {}Auto-discovery failed: {}{}".format(C_YELLOW, e, C_RESET))
        return [], []

def add_provider():
    clear()
    print_banner()
    print("  {}Add New Provider{}".format(C_BOLD + C_GREEN, C_RESET))
    print("  " + "─" * 40)
    print()
    name = input("  Provider name (e.g. zai, ollama, openrouter): ").strip()
    if not name:
        print("  {}Cancelled.{}".format(C_YELLOW, C_RESET))
        return

    base_url = input("  Base URL (e.g. https://api.z.ai/api/coding/paas/v4): ").strip()
    if not base_url:
        print("  {}Cancelled.{}".format(C_YELLOW, C_RESET))
        return

    api_key = input("  API Key: ").strip()

    # Try auto-discover
    print()
    print("  {}Discovering models...{}".format(C_DIM, C_RESET))
    filtered, all_models = discover_models(base_url, api_key)

    cfg = load_providers()
    models = filtered

    if filtered:
        print("  {}Found {} models ({} total){}".format(C_GREEN, len(filtered), len(all_models), C_RESET))
        use_discovered = input("  Use discovered models? [Y/n]: ").strip().lower()
        if use_discovered == "n":
            models = []

    if not models:
        print()
        print("  Enter models (comma-separated, e.g. qwen3.7-max,qwen3.7-plus):")
        models_input = input("  > ").strip()
        models = [m.strip() for m in models_input.split(",") if m.strip()]

    cfg["providers"][name] = {
        "base_url": base_url.rstrip("/"),
        "api_key": api_key,
        "models": models,
    }
    save_providers(cfg)
    print()
    print("  {}Provider '{}' added with {} models.{}".format(C_GREEN, name, len(models), C_RESET))

def remove_provider():
    clear()
    print_banner()
    cfg = load_providers()
    names = list(cfg["providers"].keys())
    if not names:
        print("  {}No providers configured.{}".format(C_YELLOW, C_RESET))
        return
    print("  {}Remove Provider{}".format(C_BOLD + C_RED, C_RESET))
    print()
    for i, n in enumerate(names):
        print("  {}) {}".format(i + 1, n))
    print()
    choice = input("  Remove which? (number or name, 0 to cancel): ").strip()
    if choice == "0":
        return
    try:
        idx = int(choice) - 1
        name = names[idx]
    except (ValueError, IndexError):
        name = choice
    if name in cfg["providers"]:
        del cfg["providers"][name]
        save_providers(cfg)
        print("  {}Provider '{}' removed.{}".format(C_GREEN, name, C_RESET))
    else:
        print("  {}Provider '{}' not found.{}".format(C_RED, name, C_RESET))

def list_providers():
    clear()
    print_banner()
    cfg = load_providers()
    if not cfg["providers"]:
        print("  {}No providers configured yet.{}".format(C_YELLOW, C_RESET))
        print("  Run with --add to add a provider.")
        return
    print("  {}Configured Providers{}".format(C_BOLD, C_RESET))
    print("  " + "─" * 40)
    for name, p in cfg["providers"].items():
        print()
        print_provider(name, p)

def add_custom_model():
    clear()
    print_banner()
    cfg = load_providers()
    names = list(cfg["providers"].keys())
    if not names:
        print("  {}No providers configured.{}".format(C_YELLOW, C_RESET))
        return

    print("  {}Add Custom Model to Provider{}".format(C_BOLD + C_GREEN, C_RESET))
    print()
    for i, n in enumerate(names):
        print("  {}) {}".format(i + 1, n))
    print()
    choice = input("  Select provider: ").strip()
    try:
        idx = int(choice) - 1
        name = names[idx]
    except (ValueError, IndexError):
        print("  {}Invalid choice.{}".format(C_RED, C_RESET))
        return

    print()
    model_name = input("  Model ID (e.g. qwen3-coder-plus): ").strip()
    if not model_name:
        return

    if model_name in cfg["providers"][name]["models"]:
        print("  {}Model already exists.{}".format(C_YELLOW, C_RESET))
        return

    cfg["providers"][name]["models"].append(model_name)
    save_providers(cfg)
    print("  {}Model '{}' added to provider '{}'.{}".format(C_GREEN, model_name, name, C_RESET))

# ---------------------------------------------------------------------------
# GUI config patching
# ---------------------------------------------------------------------------

def patch_gui_settings(provider_name, model_name):
    """Patch DeepSeek GUI settings to use the selected provider + model."""
    cfg = load_providers()
    provider = cfg["providers"][provider_name]

    if not GUI_SETTINGS.exists():
        print("  {}GUI settings not found at {}{}".format(C_RED, GUI_SETTINGS, C_RESET))
        print("  {}Make sure DeepSeek GUI has been run at least once.{}".format(C_YELLOW, C_RESET))
        return False

    with open(GUI_SETTINGS) as f:
        gui = json.load(f)

    base_url = provider["base_url"]
    api_key = provider["api_key"]

    # 1. Top-level provider config (what Kun actually reads)
    gui["provider"]["baseUrl"] = base_url
    gui["provider"]["apiKey"] = api_key

    # 2. Provider array (dropdown UI)
    if gui["provider"].get("providers"):
        gui["provider"]["providers"][0]["baseUrl"] = base_url
        gui["provider"]["providers"][0]["apiKey"] = api_key
        gui["provider"]["providers"][0]["models"] = provider["models"]

    # 3. Set the selected model
    gui["agents"]["kun"]["model"] = model_name

    with open(GUI_SETTINGS, "w") as f:
        json.dump(gui, f, indent=2)

    return True

def patch_kun_config(provider_name):
    """Add model profiles to Kun config."""
    cfg = load_providers()
    provider = cfg["providers"][provider_name]

    if not KUN_CONFIG.exists():
        return

    with open(KUN_CONFIG) as f:
        kun = json.load(f)

    profiles = kun.setdefault("models", {}).setdefault("profiles", {})

    # Known context windows
    ctx_map = {
        "qwen3.7-max": 1000000, "qwen3.7-plus": 1000000,
        "qwen3.6-plus": 1000000, "qwen3.6-max-preview": 262144,
        "qwen3.6-27b": 262144, "qwen3.5-plus": 1000000,
        "qwen3.5-flash": 1000000, "qwen3-coder-plus": 1000000,
        "glm-5.1": 128000, "glm-5-turbo": 128000, "glm-5": 128000,
        "glm-4.7": 128000, "glm-4.6": 128000, "glm-4.5": 128000,
        "glm-4.5-air": 128000,
        "deepseek-v4-pro": 128000, "deepseek-v4-flash": 128000,
        "deepseek-chat": 128000, "deepseek-reasoner": 128000,
    }

    for model_id in provider.get("models", []):
        if model_id not in profiles:
            ctx = ctx_map.get(model_id, 128000)
            profiles[model_id] = {
                "contextWindowTokens": ctx,
                "contextCompaction": {
                    "softThreshold": int(ctx * 0.95),
                    "hardThreshold": int(ctx * 0.98)
                },
                "inputModalities": ["text"],
                "outputModalities": ["text"],
                "supportsToolCalling": True,
                "messageParts": ["text"]
            }

    with open(KUN_CONFIG, "w") as f:
        json.dump(kun, f, indent=2)

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------

def find_gui_executable():
    """Find the DeepSeek GUI executable."""
    cfg = load_providers()
    # Check saved path
    saved = cfg.get("gui_executable", "")
    if saved and Path(saved).exists():
        return saved

    # Linux: check AppImage
    if APPIMAGE_PATH and APPIMAGE_PATH.exists():
        return str(APPIMAGE_PATH)

    # Common locations
    candidates = [
        HOME / "Applications/DeepSeek-GUI.AppImage",
        HOME / "Desktop/DeepSeek-GUI.AppImage",
        Path("/opt/DeepSeek-GUI/DeepSeek-GUI"),
        Path("/usr/bin/deepseek-gui"),
        Path("/usr/local/bin/deepseek-gui"),
        HOME / ".local/bin/deepseek-gui",
    ]

    # macOS
    if PLATFORM == "darwin":
        candidates.extend([
            HOME / "Applications/DeepSeek GUI.app",
            Path("/Applications/DeepSeek GUI.app"),
        ])

    for c in candidates:
        if c.exists():
            return str(c)

    return None

def launch_gui(provider_name, model_name):
    """Patch configs and launch DeepSeek GUI."""
    clear()
    print_banner()
    print("  {}Launching DeepSeek GUI...{}".format(C_BOLD + C_GREEN, C_RESET))
    print()
    print("  Provider:  {}{}{}".format(C_CYAN, provider_name, C_RESET))
    print("  Model:     {}{}{}".format(C_CYAN, model_name, C_RESET))

    provider = load_providers()["providers"][provider_name]
    print("  Endpoint:  {}".format(provider["base_url"]))
    print()

    # Patch configs
    print("  {}Patching GUI settings...{}".format(C_DIM, C_RESET), end=" ", flush=True)
    if not patch_gui_settings(provider_name, model_name):
        return
    print("{}OK{}".format(C_GREEN, C_RESET))

    print("  {}Patching Kun config...{}".format(C_DIM, C_RESET), end=" ", flush=True)
    patch_kun_config(provider_name)
    print("{}OK{}".format(C_GREEN, C_RESET))

    # Find executable
    gui_exe = find_gui_executable()
    if not gui_exe:
        print()
        print("  {}DeepSeek GUI not found.{}".format(C_RED, C_RESET))
        print("  Set the path manually:")
        gui_path = input("  Path to DeepSeek GUI executable: ").strip()
        if gui_path and Path(gui_path).exists():
            cfg = load_providers()
            cfg["gui_executable"] = gui_path
            save_providers(cfg)
            gui_exe = gui_path
        else:
            print("  {}Invalid path. Exiting.{}".format(C_RED, C_RESET))
            return

    # Save the executable path
    cfg = load_providers()
    cfg["gui_executable"] = gui_exe
    save_providers(cfg)

    # Kill any existing instance
    print("  {}Stopping existing GUI...{}".format(C_DIM, C_RESET), end=" ", flush=True)
    try:
        subprocess.run(["pkill", "-f", "DeepSeek-GUI"], capture_output=True, timeout=3)
    except Exception:
        pass
    print("{}OK{}".format(C_GREEN, C_RESET))

    # Launch
    print()
    print("  {}Starting GUI...{}".format(C_BOLD, C_RESET))
    print()

    cmd = [gui_exe, "--no-sandbox"] if gui_exe.endswith(".AppImage") else [gui_exe]
    try:
        subprocess.Popen(cmd, start_new_session=True,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("  {}DeepSeek GUI launched!{}".format(C_GREEN, C_RESET))
        print("  {}Select '{}' from the model dropdown and start chatting.{}".format(C_CYAN, model_name, C_RESET))
    except Exception as e:
        print("  {}Failed to launch: {}{}".format(C_RED, e, C_RESET))

# ---------------------------------------------------------------------------
# Interactive menu
# ---------------------------------------------------------------------------

def interactive_launcher():
    cfg = load_providers()
    providers = cfg.get("providers", {})

    if not providers:
        clear()
        print_banner()
        print("  {}No providers configured yet.{}".format(C_YELLOW, C_RESET))
        print("  Let's add your first provider.")
        print()
        add_provider()
        cfg = load_providers()
        providers = cfg.get("providers", {})
        if not providers:
            return

    # Main menu
    while True:
        clear()
        print_banner()

        names = list(providers.keys())
        print("  {}Select Provider{}".format(C_BOLD, C_RESET))
        print("  " + "─" * 40)
        for i, name in enumerate(names):
            p = providers[name]
            models = p.get("models", [])
            print("  {}) {} {}({} models){}".format(i + 1, name, C_DIM, len(models), C_RESET))
        print()
        print("  {}) Add provider".format(len(names) + 1))
        print("  {}) Remove provider".format(len(names) + 2))
        print("  {}) Add custom model".format(len(names) + 3))
        print("  {}) Quit".format(len(names) + 4))
        print()

        choice = input("  {}> {}".format(C_CYAN, C_RESET)).strip()
        if not choice:
            continue

        try:
            idx = int(choice) - 1
        except ValueError:
            continue

        if 0 <= idx < len(names):
            # Provider selected — pick model
            provider_name = names[idx]
            provider = providers[provider_name]
            models = provider.get("models", [])

            if not models:
                print("  {}No models configured for this provider.{}".format(C_YELLOW, C_RESET))
                input("  Press Enter to continue...")
                continue

            clear()
            print_banner()
            print("  {}Select Model{}  [{}]".format(C_BOLD, C_RESET, provider_name))
            print("  " + "─" * 40)
            for i, m in enumerate(models):
                print("  {}) {}".format(i + 1, m))
            print()
            print("  0) Back")
            print()

            mchoice = input("  {}> {}".format(C_CYAN, C_RESET)).strip()
            try:
                midx = int(mchoice) - 1
                if 0 <= midx < len(models):
                    model_name = models[midx]
                    launch_gui(provider_name, model_name)
                    return
            except ValueError:
                continue

        elif idx == len(names):
            add_provider()
            cfg = load_providers()
            providers = cfg.get("providers", {})
        elif idx == len(names) + 1:
            remove_provider()
            cfg = load_providers()
            providers = cfg.get("providers", {})
        elif idx == len(names) + 2:
            add_custom_model()
            cfg = load_providers()
            providers = cfg.get("providers", {})
        elif idx == len(names) + 3:
            print()
            print("  Bye!")
            return

def quick_launch(provider_name):
    cfg = load_providers()
    providers = cfg.get("providers", {})
    if provider_name not in providers:
        print("Provider '{}' not found. Available: {}".format(provider_name, ", ".join(providers.keys())))
        sys.exit(1)
    provider = providers[provider_name]
    models = provider.get("models", [])
    if not models:
        print("No models configured for '{}'.".format(provider_name))
        sys.exit(1)
    # Use first model
    model_name = models[0]
    launch_gui(provider_name, model_name)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg == "--add":
            add_provider()
        elif arg == "--remove":
            remove_provider()
        elif arg == "--list":
            list_providers()
        elif arg == "--model":
            add_custom_model()
        elif arg == "--quick" and len(sys.argv) > 2:
            quick_launch(sys.argv[2])
        elif arg == "--help" or arg == "-h":
            print(__doc__)
        else:
            print(__doc__)
        return

    interactive_launcher()

if __name__ == "__main__":
    main()
