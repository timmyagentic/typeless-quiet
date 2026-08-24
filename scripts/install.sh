#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
install_root="${TYPELESS_QUIET_INSTALL_DIR:-${HOME:?}/Applications}"
destination="$install_root/Typeless Quiet.app"
replace=false

if [[ "${1:-}" == "--replace" ]]; then
  replace=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--replace]" >&2
  exit 2
fi

artifact_path="$("$repo_root/scripts/build-app.sh" | tail -n 1)"
mkdir -p "$install_root"

if [[ -e "$destination" ]]; then
  if [[ "$replace" != true ]]; then
    echo "Already installed: $destination" >&2
    echo "Run with --replace to move the current copy aside and install this build." >&2
    exit 1
  fi

  backup="$install_root/Typeless Quiet.backup-$(date +%Y%m%d-%H%M%S).app"
  mv "$destination" "$backup"
  echo "Previous copy moved to: $backup"
fi

ditto "$artifact_path" "$destination"
codesign --verify --deep --strict --verbose=2 "$destination"
open "$destination"

echo "Installed and opened: $destination"
