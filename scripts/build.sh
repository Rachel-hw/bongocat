#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/build/Bongo Tap.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$project_dir/build/module-cache" "$project_dir/build/bin"
sources=("$project_dir"/Sources/*.swift "$project_dir/Tests/RunnerChecks.swift")
python3 "$project_dir/scripts/version.py" check
python3 -m unittest discover -s "$project_dir/Tests" -p 'test_*.py'
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -target "$arch-apple-macos13.0" \
    -module-cache-path "$project_dir/build/module-cache" \
    -framework AppKit -framework CoreGraphics -framework ApplicationServices \
    "${sources[@]}" -o "$project_dir/build/bin/BongoTap-$arch"
done
xcrun lipo -create "$project_dir/build/bin/BongoTap-arm64" "$project_dir/build/bin/BongoTap-x86_64" \
  -output "$app_dir/Contents/MacOS/BongoTap"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
xcrun swiftc -module-cache-path "$project_dir/build/module-cache" \
  "$project_dir/scripts/make-icon.swift" -o "$project_dir/build/bin/make-icon"
"$project_dir/build/bin/make-icon" "$project_dir/build/AppIcon.iconset"
iconutil -c icns "$project_dir/build/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
# Ad-hoc signature is for local testing; this is not Developer ID notarization.
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
"$app_dir/Contents/MacOS/BongoTap" --self-test
printf 'Built: %s\n' "$app_dir"
