#!/usr/bin/env bash
set -euo pipefail

SCENARIO="${1:-wrap-input}"
OUTPUT="${2:-/tmp/slopadeditor-debug-${SCENARIO}.png}"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

if [[ "${SLOPAD_DEBUG_BUILD:-0}" == "1" || ! -x .build/debug/SlopadEditorDebugApp ]]; then
  swift build --product SlopadEditorDebugApp
fi

if [[ ! -x .build/debug/SlopadEditorDebugApp ]]; then
  printf 'SlopadEditorDebugApp is not built. Run `swift build --product SlopadEditorDebugApp` first.\n' >&2
  exit 1
fi

.build/debug/SlopadEditorDebugApp \
  --scenario "$SCENARIO" \
  --screenshot "$OUTPUT" \
  --auto-exit

printf '%s\n' "$OUTPUT"
