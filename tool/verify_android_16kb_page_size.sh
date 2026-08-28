#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <path-to-android-shared-library>" >&2
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

echo "Inspecting Android LOAD alignment: $LIB_PATH"
file "$LIB_PATH"

load_alignments="$(readelf -lW "$LIB_PATH" | awk '$1 == "LOAD" {print $NF}')"
if [[ -z "$load_alignments" ]]; then
  echo "::error::No ELF LOAD segments found in $LIB_PATH" >&2
  exit 1
fi

while IFS= read -r alignment; do
  if [[ ! "$alignment" =~ ^0x[[:xdigit:]]+$ ]]; then
    echo "::error::Unexpected LOAD alignment value: $alignment" >&2
    exit 1
  fi
  if (( alignment < 0x4000 )); then
    echo "::error::LOAD segment alignment $alignment is below 0x4000 (16 KB)" >&2
    exit 1
  fi
done <<<"$load_alignments"

printf 'Verified LOAD alignments:\n%s\n' "$load_alignments"
