#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
app_path="${1:-}"
output_path="${2:-}"

if [[ -z "$app_path" || -z "$output_path" ]]; then
  echo "Usage: $0 path/to/Typeless\ Quiet.app path/to/output.dmg" >&2
  exit 2
fi
if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

background="$repo_root/Resources/dmg-background.png"
if [[ ! -f "$background" ]]; then
  echo "DMG background not found: $background" >&2
  exit 1
fi

volume_name="Typeless Quiet"
temp_root="$(mktemp -d /tmp/typeless-quiet-dmg.XXXXXX)"
staging="$temp_root/staging"
mount_point="/Volumes/$volume_name"
read_write_dmg="$temp_root/layout-rw.dmg"
mounted=false

cleanup() {
  if [[ "$mounted" == true ]]; then
    hdiutil detach "$mount_point" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$temp_root"
}
trap cleanup EXIT

if mount | grep -Fq "on $mount_point "; then
  echo "A volume is already mounted at $mount_point" >&2
  exit 1
fi

mkdir -p "$staging/.background" "$(dirname "$output_path")"
ditto "$app_path" "$staging/Typeless Quiet.app"
ln -s /Applications "$staging/Applications"
cp "$background" "$staging/.background/background.png"

raw_kb="$(du -sk "$staging" | awk '{print $1}')"
size_kb=$((raw_kb + raw_kb / 5 + 32768))

hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$staging" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -size "${size_kb}k" \
  "$read_write_dmg" >/dev/null

hdiutil attach \
  "$read_write_dmg" \
  -mountpoint "$mount_point" \
  -nobrowse \
  -noautoopen >/dev/null
mounted=true

osascript <<'APPLESCRIPT'
with timeout of 30 seconds
  tell application "Finder"
    tell disk "Typeless Quiet"
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set sidebar width of container window to 0
      set the bounds of container window to {180, 100, 840, 520}

      set viewOptions to the icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 96
      set text size of viewOptions to 12
      set background picture of viewOptions to file ".background:background.png"

      set position of item "Typeless Quiet.app" of container window to {165, 225}
      set position of item "Applications" of container window to {495, 225}

      update without registering applications
      delay 2
      close
    end tell
  end tell
end timeout
APPLESCRIPT

sync
sleep 2
hdiutil detach "$mount_point" -quiet
mounted=false

hdiutil convert \
  "$read_write_dmg" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$output_path" >/dev/null

echo "$output_path"
