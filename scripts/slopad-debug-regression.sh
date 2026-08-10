#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:-/tmp/slopad-debug-regression}"
mkdir -p "$OUTPUT_DIR"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

if [[ "${SLOPAD_DEBUG_BUILD:-0}" == "1" || ! -x .build/debug/SlopadDebugApp ]]; then
  swift build --product SlopadDebugApp
fi

if [[ ! -x .build/debug/SlopadDebugApp ]]; then
  printf 'SlopadDebugApp is not built. Run `swift build --product SlopadDebugApp` first.\n' >&2
  exit 1
fi

SCENARIOS=(
  wrap-input
  gutter-selection
  gutter-drag-selection
  text-drag-selection
  text-drag-cross-block
  double-click-word-selection
  double-click-block-text-selection
  drag-reorder
  click-tail
  click-todo
  todo-checkbox-control
  floating-toolbar-text
  floating-toolbar-block
  ime-composition
  ime-marked-callback
  ime-unmark-callback
  move-down
  move-up
  move-right
  move-left
  prefix-list
  prefix-heading
  native-insert
  shift-enter
  enter-split
  tail-enter-split
  backspace-merge
  soft-line-down
  scroll-down
  scroll-up
)

for scenario in "${SCENARIOS[@]}"; do
  scripts/slopad-debug-screenshot.sh "$scenario" "$OUTPUT_DIR/${scenario}.png"
done

printf 'Slopad debug regression screenshots written to %s\n' "$OUTPUT_DIR"
