#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
configuration="${CONFIGURATION:-release}"
artifact_root="${ARTIFACT_ROOT:-$repo_root/dist}"
app_path="$artifact_root/Typeless Quiet.app"
code_sign_identity="${CODE_SIGN_IDENTITY:--}"

swift build \
  --package-path "$repo_root" \
  --configuration "$configuration" \
  --product TypelessQuiet

binary_dir="$(swift build \
  --package-path "$repo_root" \
  --configuration "$configuration" \
  --show-bin-path)"

if [[ ! -x "$binary_dir/TypelessQuiet" ]]; then
  echo "Built executable is missing: $binary_dir/TypelessQuiet" >&2
  exit 1
fi

if [[ -e "$app_path" ]]; then
  rm -rf "$app_path"
fi

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/TypelessQuiet" "$app_path/Contents/MacOS/TypelessQuiet"
cp "$repo_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$repo_root/Resources/PkgInfo" "$app_path/Contents/PkgInfo"
cp "$repo_root/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
chmod 755 "$app_path/Contents/MacOS/TypelessQuiet"

plutil -lint "$app_path/Contents/Info.plist" >/dev/null
codesign_arguments=(
  --force
  --sign "$code_sign_identity"
  --options runtime
)
if [[ "$code_sign_identity" == "-" ]]; then
  codesign_arguments+=(--timestamp=none)
else
  codesign_arguments+=(--timestamp)
fi
codesign "${codesign_arguments[@]}" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

echo "$app_path"
