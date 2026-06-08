#!/usr/bin/env python3
"""DeepSeek GUI X Edition - Installation Script

Configures an existing DeepSeek GUI installation to support GLM models
by applying the buildUrl patch and updating configuration files.

Prerequisites:
- DeepSeek GUI AppImage must be mounted or extracted
- The Kun runtime files will be copied from the installed location
"""
import json, os, shutil, argparse, subprocess, glob

GLM_MODELS = ['glm-5.1', 'glm-5-turbo', 'glm-5', 'glm-4.7', 'glm-4.6', 'glm-4.5', 'glm-4.5-air']
DEEPSEEK_MODELS = ['deepseek-v4-flash', 'deepseek-v4-pro']
ALL_MODELS = DEEPSEEK_MODELS + GLM_MODELS

def find_kun_source():
    """Find Kun runtime from mounted AppImage or installed location."""
    # Check mounted AppImages
    for d in os.listdir('/tmp'):
        if d.startswith('.mount_DeepSe'):
            kun_dir = f'/tmp/{d}/resources/app.asar.unpacked/kun'
            if os.path.isdir(kun_dir):
                return kun_dir
    # Check common install locations
    for path in [
        os.path.expanduser('~/DeepSeek-GUI/dist/linux-unpacked/resources/app.asar.unpacked/kun'),
        os.path.expanduser('~/Applications/DeepSeek-GUI/resources/app.asar.unpacked/kun'),
    ]:
        if os.path.isdir(path):
            return path
    # Try extracting from AppImage
    appimage = os.path.expanduser('~/Applications/DeepSeek-GUI.AppImage')
    if os.path.exists(appimage):
        print(f'AppImage found at {appimage} but not mounted.')
        print('Please launch the GUI first, then run this script again.')
        print('Alternatively, extract it: ')
        print(f'  {appimage} --appimage-extract')
        print(f'  Then pass --kun-source /tmp/squashfs-root/resources/app.asar.unpacked/kun')
    return None

def copy_kun_runtime(source, target):
    """Copy Kun runtime from source to target."""
    if os.path.exists(target):
        shutil.rmtree(target)
    shutil.copytree(source, target)
    print(f'Copied Kun runtime: {source} -> {target}')

def apply_patch(target_dir, repo_dir):
    """Apply the buildUrl patch to the Kun model client."""
    patched_file = os.path.join(repo_dir, 'patches', 'deepseek-compat-model-client.patched.js')
    target_file = os.path.join(target_dir, 'dist', 'adapters', 'model', 'deepseek-compat-model-client.js')
    if os.path.exists(patched_file) and os.path.exists(target_file):
        shutil.copy2(patched_file, target_file)
        print(f'Applied buildUrl patch to {target_file}')
    else:
        print(f'Warning: Could not apply patch')
        print(f'  Patched file: {patched_file} (exists: {os.path.exists(patched_file)})')
        print(f'  Target file: {target_file} (exists: {os.path.exists(target_file)})')

def patch_gui_settings(settings_path):
    """Update GUI settings to include GLM models and binaryPath override."""
    with open(settings_path, 'r') as f:
        settings = json.load(f)
    
    provider = settings.get('provider', {}).get('providers', [{}])[0]
    current_models = provider.get('models', [])
    for model in ALL_MODELS:
        if model not in current_models:
            current_models.append(model)
    settings['provider']['providers'][0]['models'] = current_models
    
    settings['agents']['kun']['binaryPath'] = os.path.expanduser('~/.deepseekgui/kun-patched')
    
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
    print(f'Updated GUI settings: {settings_path}')

def patch_kun_config():
    """Update Kun config to include GLM model profiles."""
    config_path = os.path.expanduser('~/.deepseekgui/kun/config.json')
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    profiles = config.get('models', {}).get('profiles', {})
    for model in GLM_MODELS:
        if model not in profiles:
            profiles[model] = {
                'contextWindowTokens': 128000,
                'contextCompaction': {'softThreshold': 120000, 'hardThreshold': 124000},
                'inputModalities': ['text'], 'outputModalities': ['text'],
                'supportsToolCalling': True, 'messageParts': ['text']
            }
    config['models']['profiles'] = profiles
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    print(f'Updated Kun config: {config_path}')

def main():
    parser = argparse.ArgumentParser(description='Install DeepSeek GUI X Edition')
    parser.add_argument('--gui-settings', default=os.path.expanduser('~/.config/deepseek-gui/deepseek-gui-settings.json'),
                        help='Path to deepseek-gui-settings.json')
    parser.add_argument('--kun-source', default=None, help='Path to Kun runtime source directory')
    parser.add_argument('--repo-dir', default=os.path.dirname(os.path.abspath(__file__)), help='Path to this repo')
    args = parser.parse_args()
    
    repo_dir = os.path.abspath(args.repo_dir)
    target = os.path.expanduser('~/.deepseekgui/kun-patched')
    
    print('=== DeepSeek GUI X Edition Installer ===')
    print()
    
    # Step 1: Find and copy Kun runtime
    print('[1/4] Locating Kun runtime...')
    kun_source = args.kun_source or find_kun_source()
    if not kun_source:
        print('ERROR: Could not find Kun runtime.')
        print('Please pass --kun-source pointing to the kun directory from your installation.')
        return 1
    print(f'  Found at: {kun_source}')
    
    print('[2/4] Copying Kun runtime...')
    copy_kun_runtime(kun_source, target)
    
    # Step 2: Apply patch
    print('[3/4] Applying buildUrl patch...')
    apply_patch(target, repo_dir)
    
    # Step 3: Update configs
    print('[4/4] Updating configuration...')
    patch_kun_config()
    patch_gui_settings(args.gui_settings)
    
    print()
    print('=== Installation Complete ===')
    print('Please restart DeepSeek GUI to apply changes.')
    return 0

if __name__ == '__main__':
    exit(main())
