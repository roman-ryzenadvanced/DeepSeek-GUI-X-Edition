#!/usr/bin/env python3
"""
Patch Kun config.json with GLM model profiles from the X Edition config.
Merges GLM profiles into an existing config without overwriting other entries.

Usage:
    python3 patch-kun-config.py <target-config> <x-edition-config>
"""

import json
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 3:
        print("Usage: patch-kun-config.py <target-config> <x-edition-config>")
        sys.exit(1)

    target_path = Path(sys.argv[1])
    xedition_path = Path(sys.argv[2])

    if not target_path.exists():
        print(f"Error: Target config not found: {target_path}")
        sys.exit(1)

    if not xedition_path.exists():
        print(f"Error: X Edition config not found: {xedition_path}")
        sys.exit(1)

    target = json.loads(target_path.read_text())
    xedition = json.loads(xedition_path.read_text())

    # Ensure models.profiles exists
    if "models" not in target:
        target["models"] = {}
    if "profiles" not in target["models"]:
        target["models"]["profiles"] = {}

    # Merge GLM profiles
    added = 0
    for model_id, profile in xedition.get("models", {}).get("profiles", {}).items():
        if model_id.startswith("glm-"):
            target["models"]["profiles"][model_id] = profile
            added += 1

    target_path.write_text(json.dumps(target, indent=2, ensure_ascii=False) + "\n")
    print(f"  Added {added} GLM model profiles to {target_path}")


if __name__ == "__main__":
    main()
