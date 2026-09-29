#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/build/Bongo Tap.app"
app_version="$(python3 "$project_dir/scripts/version.py" current)"
image_path="$project_dir/dist/Bongo-Tap-$app_version-universal.dmg"
if [[ ! -d "$app_dir" ]]; then
  printf 'Build first: bash scripts/build.sh\n' >&2
  exit 1
fi
python3 "$project_dir/scripts/version.py" check --bundle "$app_dir"
mkdir -p "$project_dir/dist"
staging_dir="$(mktemp -d "$project_dir/build/dmg-staging.XXXXXX")"
ditto "$app_dir" "$staging_dir/Bongo Tap.app"
ln -s /Applications "$staging_dir/Applications"
sed "s/@VERSION@/$app_version/g" "$project_dir/Resources/安装与使用.txt" > "$staging_dir/安装与使用.txt"
hdiutil create -volname 'Bongo Tap' -srcfolder "$staging_dir" -ov -format UDZO "$image_path"
hdiutil verify "$image_path"
(
  cd "$project_dir/dist"
  shasum -a 256 "$(basename "$image_path")" > "$(basename "$image_path").sha256"
)
printf 'Packaged: %s\n' "$image_path"
