# Benchmark Baselines

This folder keeps checked-in CSV baselines used to compare editor layout/index changes.

## Height Index Storage Experiment

Generated on 2026-07-06 for the RBTree-vs-array `BlockHeightIndexStorage`
experiment.

- `height-index-rbtree-storage-extended-20260706.csv`: session benchmark using the default
  `RBTreeBlockHeightIndexStorage`.
- `height-index-array-storage-extended-20260706.csv`: same session benchmark compiled with
  `-Xswiftc -DSLOPAD_HEIGHT_INDEX_ARRAY`, using `ArrayBlockHeightIndexStorage`.
- `height-index-storage-extended-compare-20260706.csv`: side-by-side comparison of the two
  session benchmark CSVs. `deltaMs = arrayTotalMs - rbtreeTotalMs`; negative means array is
  faster, positive means RBTree is faster.
- `height-index-micro-compare-20260706.csv`: micro benchmark comparison for direct height
  index build/query/update operations.

The extended session benchmark uses block counts `100,1000,10000` and includes normal
layout paths plus structural cases: `subtreeDelete`, `subtreeReorder`, and
`heightExpansionHitTest`.

See `docs/HEIGHT_INDEX_STORAGE_EXPERIMENT.md` for commands, interpretation, and decision.

## AppKit UI Benchmark Sweep

Generated on 2026-07-06 for the real `SlopadUIBenchmarkApp` AppKit/TextKit2 UI benchmark.

- `appkit-ui-rbtree-20260706.csv`: raw frame samples using the default
  `RBTreeBlockHeightIndexStorage`.
- `appkit-ui-array-20260706.csv`: raw frame samples compiled with
  `-Xswiftc -DSLOPAD_HEIGHT_INDEX_ARRAY`.
- `appkit-ui-summary-20260706.csv`: aggregate FPS/frame/render/display/draw metrics by
  storage, scenario, and block count.
- `appkit-ui-storage-compare-20260706.csv`: side-by-side AppKit UI frame comparison.
- `appkit-ui-subtree-rbtree-20260706.csv`: raw AppKit subtree frame samples using the
  default `RBTreeBlockHeightIndexStorage`.
- `appkit-ui-subtree-array-20260706.csv`: raw AppKit subtree frame samples compiled with
  `-Xswiftc -DSLOPAD_HEIGHT_INDEX_ARRAY`.
- `appkit-ui-subtree-summary-20260706.csv`: aggregate metrics for subtree UI scenarios.
- `appkit-ui-subtree-storage-compare-20260706.csv`: side-by-side AppKit subtree UI
  comparison.

The UI sweep uses block counts `100,1000,10000`, 60 frames per scenario, and scenarios
`scroll`, `native-insert`, `composition`, `height-expansion`, `block-selection`,
`block-reorder`, and `mixed`.

The subtree UI follow-up uses the same block counts and 60 frames for `subtree-delete`
and `subtree-reorder`. Those scenarios build a subtree fixture with `6`, `50`, and `200`
visible nodes at `100`, `1000`, and `10000` blocks respectively, then drive the AppKit
host through block range selection plus delete or drag reorder.

See `docs/APPKIT_UI_BENCHMARK_RESULTS.md` for commands and AppKit host-frame
interpretation. See `docs/HEIGHT_INDEX_STORAGE_EXPERIMENT.md` for the storage decision.

## Runtime Style Replacement

Generated on 2026-07-17 for the synchronized AppKit runtime style contract.

- `appkit-runtime-style-summary-20260717.csv`: release-build aggregate metrics for the
  `style-change` scenario at `100`, `1000`, and `10000` blocks, with 60 frames at each
  scale.

The scenario alternates two geometry-affecting `TextKitEditorStyle` values through the
public `updateEditorStyle(_:)` action. Operation time therefore includes pipeline creation,
engine backend replacement, full text-layout invalidation, and synchronized surface
rendering. Forced AppKit display and TextKit drawing are recorded separately in the same
frame.

## Unicode Text Navigation

Generated on 2026-07-17 for the TextKit2 Unicode navigation contract.

- `appkit-unicode-navigation-summary-20260717.csv`: release-build aggregate metrics for
  mixed Korean/English/Hebrew/emoji word navigation. One sweep varies total document
  blocks at `100`, `1000`, and `10000`; a second holds the document at 100 blocks and
  varies the active paragraph at `100`, `1000`, and `10000` graphemes.

Each case measures 60 alternating native word-left/word-right operations. The long-text
sweep keeps the caret near the paragraph end so grapheme/UTF-16 conversion and native
segmentation costs are not hidden by a prefix-only position. Cold first-operation time is
recorded separately from median and p95 steady-state input cost. The checked-in values are
post-optimization: grapheme/UTF-16 boundary maps are built lazily per prepared request and
then reused for constant-time conversion.
