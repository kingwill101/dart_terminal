#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GHOSTTY_DIR="${1:-$ROOT_DIR/pkgs/vte/ghostty_vte/third_party/ghostty}"
PATCH_DIR="$ROOT_DIR/pkgs/vte/ghostty_vte/patches"

shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)

if [[ ${#patches[@]} -eq 0 ]]; then
  echo "No bundled Ghostty source patches found in $PATCH_DIR"
  exit 0
fi

for patch in "${patches[@]}"; do
  patch_name="$(basename "$patch")"
  if git -C "$GHOSTTY_DIR" apply --reverse --check "$patch" >/dev/null 2>&1; then
    echo "Patch already applied: $patch_name"
    continue
  fi

  git -C "$GHOSTTY_DIR" apply --check "$patch"
  git -C "$GHOSTTY_DIR" apply "$patch"
  echo "Applied patch: $patch_name"
done
