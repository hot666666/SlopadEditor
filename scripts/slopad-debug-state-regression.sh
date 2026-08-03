#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:-/tmp/slopad-debug-state-regression}"
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
  click-todo
  text-drag-selection
  text-drag-clamp-to-block
  double-click-word-selection
  double-click-block-text-selection
  drag-reorder
  click-tail
  move-down
  move-right
  unicode-navigation
  prefix-list
  prefix-heading
  native-insert
  enter-split
  tail-enter-split
  scroll-down
  scroll-up
)

for scenario in "${SCENARIOS[@]}"; do
  .build/debug/SlopadDebugApp \
    --scenario "$scenario" \
    --screenshot "$OUTPUT_DIR/${scenario}.png" \
    --assert-state \
    --auto-exit
done

printf 'Slopad debug state regression passed with screenshots in %s\n' "$OUTPUT_DIR"
