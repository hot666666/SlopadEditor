#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:-/tmp/slopadeditor-debug-state-regression}"
mkdir -p "$OUTPUT_DIR"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

if [[ "${SLOPAD_DEBUG_BUILD:-0}" == "1" || ! -x .build/debug/SlopadEditorDebugApp ]]; then
  swift build --product SlopadEditorDebugApp
fi

if [[ ! -x .build/debug/SlopadEditorDebugApp ]]; then
  printf 'SlopadEditorDebugApp is not built. Run `swift build --product SlopadEditorDebugApp` first.\n' >&2
  exit 1
fi

SCENARIOS=(
  click-todo
  todo-checkbox-control
  floating-toolbar-text
  floating-toolbar-block
  text-drag-selection
  text-drag-cross-block
  double-click-word-selection
  double-click-block-text-selection
  drag-reorder
  click-tail
  move-down
  move-right
  unicode-navigation
  prefix-list
  prefix-heading
  slash-heading
  native-insert
  enter-split
  tail-enter-split
  scroll-down
  scroll-up
)

for scenario in "${SCENARIOS[@]}"; do
  .build/debug/SlopadEditorDebugApp \
    --scenario "$scenario" \
    --screenshot "$OUTPUT_DIR/${scenario}.png" \
    --assert-state \
    --auto-exit
done

printf 'SlopadEditor debug state regression passed with screenshots in %s\n' "$OUTPUT_DIR"
