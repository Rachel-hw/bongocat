#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
probe_dir="$project_dir/build/background-probe"
mkdir -p "$probe_dir" "$project_dir/build/module-cache"
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "$project_dir/build/module-cache" \
  -framework AppKit -framework CoreGraphics -framework ApplicationServices \
  "$project_dir"/Experiments/BackgroundProbe/*.swift "$project_dir/Sources/AccessibilityPermission.swift" \
  -o "$probe_dir/Probe"
"$probe_dir/Probe" --self-test
python3 - "$probe_dir" <<'PY'
from pathlib import Path
import plistlib
import shutil
import sys
root = Path(sys.argv[1])
for name, identifier, role in [('Bongo Tap Lab', 'local.bongocat.tap.probe', 'sender'),
                               ('Bongo Input Check', 'local.bongocat.tap.input-check', 'receiver')]:
    contents = root / (name + '.app') / 'Contents'
    (contents / 'MacOS').mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / 'Probe', contents / 'MacOS' / 'Probe')
    metadata = dict(CFBundleExecutable='Probe', CFBundleIdentifier=identifier,
                    CFBundleName=name, CFBundleDisplayName=name, CFBundlePackageType='APPL',
                    CFBundleShortVersionString='0.1.0', CFBundleVersion='1', LSMinimumSystemVersion='13.0',
                    NSHighResolutionCapable=True, ProbeRole=role, ProbeResultDirectory=str(root / 'results'))
    with (contents / 'Info.plist').open('wb') as f:
        plistlib.dump(metadata, f)
PY
for name in 'Bongo Tap Lab' 'Bongo Input Check'; do
  codesign --force --sign - "$probe_dir/$name.app"
  codesign --verify --strict "$probe_dir/$name.app"
done
printf 'Built experiment apps: %s\n' "$probe_dir"
