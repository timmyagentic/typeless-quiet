#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

swift test --package-path "$repo_root"
swift build \
  --package-path "$repo_root" \
  --configuration release \
  --product TypelessQuiet

app_path="$("$repo_root/scripts/build-app.sh" | tail -n 1)"
binary_path="$app_path/Contents/MacOS/TypelessQuiet"

plutil -lint "$app_path/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app_path"
test "$(plutil -extract CFBundleIdentifier raw -o - "$app_path/Contents/Info.plist")" = \
  "io.github.timmyagentic.TypelessQuiet"
test "$(plutil -extract LSUIElement raw -o - "$app_path/Contents/Info.plist")" = "true"
test -x "$binary_path"

if otool -L "$binary_path" | grep -Eiq 'Hammerspoon|node'; then
  echo "Unexpected third-party runtime dependency found" >&2
  exit 1
fi

git -C "$repo_root" diff --check

echo "Verified: $app_path"
