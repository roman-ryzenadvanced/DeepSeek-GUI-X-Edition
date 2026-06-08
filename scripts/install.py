#!/usr/bin/env python3
"""
DeepSeek GUI X Edition - Install Script
Merges GLM model configuration into an existing DeepSeek GUI settings file.

Usage:
    python3 install.py --gui-settings <path-to-deepseek-gui-settings.json>
"""

import argparse
import json
import sys
import os
from pathlib import Path


GLM_MODELS = [
    "glm-5.1",
    "glm-5-turbo",
    "glm-5",
    "glm-4.7",
    "glm-4.6",
    "glm-4.5",
    "glm-4.5-air",
]

# Load the X Edition config as reference for what we need to merge
SCRIPT_DIR = Path(__file__).resolve().parent
X_EDITION_SETTINGS = SCRIPT_DIR.parent / "config" / "gui-settings.json"
X_EDITION_KUN_CONFIG = SCRIPT_DIR.parent / "config" / "kun-config.json"


def load_json(path: str) -> dict:
    with open(path, "r") as f:
        return json.load(f)


def save_json(path: str, data: dict) -> None:
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def merge_glm_models(settings: dict) -> dict:
    """Add GLM models to the provider models list if not already present."""
    if "provider" not in settings:
        settings["provider"] = {}
    if "providers" not in settings["provider"]:
        settings["provider"]["providers"] = []

    for provider in settings["provider"]["providers"]:
        if "models" not in provider:
            provider["models"] = []
        for model in GLM_MODELS:
            if model not in provider["models"]:
                provider["models"].append(model)

    return settings


def set_binary_path(settings: dict, binary_path: str = "~/.deepseekgui/kun-patched") -> dict:
    """Set the Kun binaryPath override in settings."""
    if "agents" not in settings:
        settings["agents"] = {}
    if "kun" not in settings["agents"]:
        settings["agents"]["kun"] = {}

    settings["agents"]["kun"]["binaryPath"] = binary_path
    return settings


def merge_kun_config(target_config_path: str) -> None:
    """Merge GLM model profiles into Kun config.json."""
    if not os.path.exists(target_config_path):
        print(f"  Kun config not found at {target_config_path}, copying full config.")
        os.makedirs(os.path.dirname(target_config_path), exist_ok=True)
        if X_EDITION_KUN_CONFIG.exists():
            import shutil
            shutil.copy2(str(X_EDITION_KUN_CONFIG), target_config_path)
        return

    target = load_json(target_config_path)
    x_config = load_json(str(X_EDITION_KUN_CONFIG))

    if "models" not in target:
        target["models"] = {}
    if "profiles" not in target["models"]:
        target["models"]["profiles"] = {}

    # Merge GLM profiles
    for model_id, profile in x_config.get("models", {}).get("profiles", {}).items():
        if model_id.startswith("glm-"):
            target["models"]["profiles"][model_id] = profile

    save_json(target_config_path, target)
    print(f"  Kun config updated with GLM profiles: {target_config_path}")


def main():
    parser = argparse.ArgumentParser(description="Install DeepSeek GUI X Edition patches")
    parser.add_argument("--gui-settings", required=True, help="Path to deepseek-gui-settings.json")
    parser.add_argument("--binary-path", default="~/.deepseekgui/kun-patched", help="Custom Kun binary path")
    parser.add_argument("--kun-config", default=None, help="Path to Kun config.json to patch")
    args = parser.parse_args()

    gui_settings_path = args.gui_settings

    if not os.path.exists(gui_settings_path):
        print(f"Error: Settings file not found: {gui_settings_path}")
        sys.exit(1)

    # Backup original
    backup_path = gui_settings_path + ".bak"
    if not os.path.exists(backup_path):
        import shutil
        shutil.copy2(gui_settings_path, backup_path)
        print(f"  Backup created: {backup_path}")

    # Load and merge
    settings = load_json(gui_settings_path)
    settings = merge_glm_models(settings)
    settings = set_binary_path(settings, args.binary_path)

    save_json(gui_settings_path, settings)
    print(f"  GUI settings updated: {gui_settings_path}")
    print(f"    Added GLM models: {', '.join(GLM_MODELS)}")
    print(f"    Set binaryPath: {args.binary_path}")

    # Optionally merge Kun config
    kun_config_path = args.kun_config or os.path.expanduser("~/.deepseekgui/kun/config.json")
    merge_kun_config(kun_config_path)

    print("\n  Done. Restart DeepSeek GUI to apply changes.")


if __name__ == "__main__":
    main()
