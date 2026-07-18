#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
output_dir="$project_dir/outputs"
app_dir="$output_dir/LumaDeck.app"

cd "$project_dir"
swift build -c "$configuration"
binary_path="$(swift build -c "$configuration" --show-bin-path)/LumaDeck"

mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_path" "$app_dir/Contents/MacOS/LumaDeck"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
