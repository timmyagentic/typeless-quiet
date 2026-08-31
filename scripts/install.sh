#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
install_root="${TYPELESS_PLUSPLUS_INSTALL_DIR:-${TYPELESS_QUIET_INSTALL_DIR:-${HOME:?}/Applications}}"
destination="$install_root/Typeless++.app"
legacy_destination="$install_root/Typeless Quiet.app"
replace=false

if [[ "${1:-}" == "--replace" ]]; then
  replace=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--replace]" >&2
  exit 2
fi

artifact_path="$("$repo_root/scripts/build-app.sh" | tail -n 1)"
mkdir -p "$install_root"

if [[ -e "$destination" && -e "$legacy_destination" ]]; then
  echo "Both current and legacy app copies exist:" >&2
  echo "  $destination" >&2
  echo "  $legacy_destination" >&2
  echo "Move one copy aside before installing to avoid duplicate bundle identities." >&2
  exit 1
fi

existing_destination=""
if [[ -e "$destination" ]]; then
  existing_destination="$destination"
elif [[ -e "$legacy_destination" ]]; then
  existing_destination="$legacy_destination"
fi

if [[ -n "$existing_destination" ]]; then
  if [[ "$replace" != true ]]; then
    echo "Already installed: $existing_destination" >&2
    echo "Run with --replace to move the current copy aside and install this build." >&2
    exit 1
  fi

  if [[ "$existing_destination" == "$legacy_destination" ]]; then
    backup="$install_root/Typeless Quiet.legacy-backup-$(date +%Y%m%d-%H%M%S).app"
  else
    backup="$install_root/Typeless++.backup-$(date +%Y%m%d-%H%M%S).app"
  fi
  mv "$existing_destination" "$backup"
  echo "Previous copy moved to: $backup"
fi

ditto "$artifact_path" "$destination"
codesign --verify --deep --strict --verbose=2 "$destination"
if [[ "${TYPELESS_PLUSPLUS_SKIP_OPEN:-false}" != "true" ]]; then
  open "$destination"
fi

echo "Installed: $destination"
