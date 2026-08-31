#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

swift test --package-path "$repo_root"
swift build \
  --package-path "$repo_root" \
  --configuration release \
  --product TypelessPlusPlus

app_path="$("$repo_root/scripts/build-app.sh" | tail -n 1)"
binary_path="$app_path/Contents/MacOS/TypelessPlusPlus"

test "$(basename "$app_path")" = "Typeless++.app"
plutil -lint "$app_path/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app_path"
# The legacy identifier intentionally preserves Accessibility, preferences, and login items.
test "$(plutil -extract CFBundleIdentifier raw -o - "$app_path/Contents/Info.plist")" = \
  "io.github.timmyagentic.TypelessQuiet"
test "$(plutil -extract CFBundleDisplayName raw -o - \
  "$app_path/Contents/Info.plist")" = "Typeless++"
test "$(plutil -extract CFBundleName raw -o - \
  "$app_path/Contents/Info.plist")" = "Typeless++"
test "$(plutil -extract CFBundleExecutable raw -o - \
  "$app_path/Contents/Info.plist")" = "TypelessPlusPlus"
test "$(plutil -extract CFBundleShortVersionString raw -o - \
  "$app_path/Contents/Info.plist")" = "0.1.5"
test "$(plutil -extract CFBundleVersion raw -o - \
  "$app_path/Contents/Info.plist")" = "6"
test "$(plutil -extract LSUIElement raw -o - "$app_path/Contents/Info.plist")" = "true"
test "$(plutil -extract CFBundleIconFile raw -o - "$app_path/Contents/Info.plist")" = "AppIcon"
test -x "$binary_path"
test -f "$app_path/Contents/Resources/AppIcon.icns"
cmp -s "$repo_root/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"

if otool -L "$binary_path" | grep -Eiq 'Hammerspoon|node'; then
  echo "Unexpected third-party runtime dependency found" >&2
  exit 1
fi

git -C "$repo_root" diff --check

echo "Verified: $app_path"
