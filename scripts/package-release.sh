#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
info_plist="$project_dir/Resources/Info.plist"
output_dir="$project_dir/outputs"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Invalid CFBundleShortVersionString: $version" >&2
    exit 1
fi

"$project_dir/scripts/build-app.sh" "$configuration"

app_path="$output_dir/LumaDeck.app"
archive_path="$output_dir/LumaDeck-macOS-v${version}.zip"
checksum_path="$archive_path.sha256"

codesign --verify --deep --strict --verbose=2 "$app_path"
rm -f "$archive_path" "$checksum_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
unzip -t "$archive_path" >/dev/null

cd "$output_dir"
shasum -a 256 "${archive_path:t}" > "${checksum_path:t}"

echo "$archive_path"
echo "$checksum_path"
