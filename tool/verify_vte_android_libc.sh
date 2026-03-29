#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <path-to-libghostty-vt.so>" >&2
  exit 64
fi

if ! command -v readelf >/dev/null 2>&1; then
  echo "readelf is required but was not found on PATH." >&2
  exit 69
fi

LIB_INPUT="$1"
LIB_PATH="$(readlink -f "$LIB_INPUT" 2>/dev/null || realpath "$LIB_INPUT" 2>/dev/null || printf '%s' "$LIB_INPUT")"

if [[ ! -f "$LIB_PATH" ]]; then
  echo "Shared library not found: $LIB_INPUT" >&2
  exit 66
fi

echo "Inspecting Android library: $LIB_PATH"
file "$LIB_PATH"

dynamic_section="$(readelf -d "$LIB_PATH")"
printf '%s\n' "$dynamic_section"

if ! grep -Fq 'Shared library: [libc.so]' <<<"$dynamic_section"; then
  echo "::error::Android libghostty-vt.so is missing a NEEDED entry for libc.so" >&2
  exit 1
fi

echo "Verified: Android libghostty-vt.so links against libc.so"
