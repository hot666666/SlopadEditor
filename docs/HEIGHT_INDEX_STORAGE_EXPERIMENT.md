# Height Index Storage Experiment

Date: 2026-07-06

## Purpose

`BlockHeightIndexStorage` owns block height/y prefix-sum lookup inside `BlockLayout`.
This experiment checks whether a simpler array-backed storage with a lazy prefix-sum cache
can replace or complement the tree implementation.

## Result Summary

The array-backed implementation is simple and is fast when the editor mostly builds or
scans ordered height entries. In full rebuild/read-heavy paths such as initial render,
width changes, and style relayouts, contiguous storage plus low lazy prefix-rebuild
overhead often made the array faster at `1000` and `10000` blocks.

That result does not hold for block-editor structural edits. When a subtree is deleted or
moved in the middle of a large document, the array implementation must rewrite ordered
indices after the splice. Even when the changed subtree has only `200` nodes, the cost
rises sharply as document size grows. RBTree has higher implementation complexity and
does not win every read-heavy case, but it keeps middle-range delete/reorder cost within
an acceptable range, so it remains the default storage.

In short:

| Workload type                       | Array result              | RBTree result             | Decision impact                         |
| ----------------------------------- | ------------------------- | ------------------------- | --------------------------------------- |
| Full rebuild / read-mostly layout   | Simple and often fast     | Acceptable, sometimes slow | Not enough to choose array              |
| Single-block edits                  | Mostly similar            | Mostly similar            | Tie-level for default choice            |
| Large-document subtree delete/move  | Cost spikes sharply       | Stays sufficiently bounded | Deciding evidence for RBTree as default |

## Implementation

- Private RBTree implementation: default storage. Uses `PrefixSumRedBlackTree` and keeps
  node handles by `BlockID`.
- Private array implementation: experimental storage. Keeps ordered internal
  `BlockHeightIndexStorage.Entry` values, `BlockID -> Int`, and lazily rebuilt prefix
  sums.
- Compile-time selection:

```sh
# Default RBTree storage
swift run -c release -Xswiftc -DSLOPAD_BENCHMARK_INSTRUMENTATION SlopadSessionBenchmark ...

# Experimental array storage
swift run -c release -Xswiftc -DSLOPAD_BENCHMARK_INSTRUMENTATION -Xswiftc -DSLOPAD_HEIGHT_INDEX_ARRAY SlopadSessionBenchmark ...
```

## Baseline Files

- `Benchmarks/Baselines/height-index-rbtree-storage-extended-20260706.csv`
- `Benchmarks/Baselines/height-index-array-storage-extended-20260706.csv`
- `Benchmarks/Baselines/height-index-storage-extended-compare-20260706.csv`
- `Benchmarks/Baselines/height-index-micro-compare-20260706.csv`

Use `height-index-storage-extended-compare-20260706.csv` for side-by-side decisions.

- `deltaMs = arrayTotalMs - rbtreeTotalMs`
- `deltaPct < 0`: array storage is faster.
- `deltaPct > 0`: RBTree storage is faster.

## Session Benchmark Commands

```sh
swift run -c release -Xswiftc -DSLOPAD_BENCHMARK_INSTRUMENTATION \
  SlopadSessionBenchmark \
  --block-counts 100,1000,10000 \
  --iterations 3 \
  --output /tmp/slopad-session-benchmark-rbtree-storage-extended-100-1000-10000-20260706.csv
```

```sh
swift run -c release \
  -Xswiftc -DSLOPAD_BENCHMARK_INSTRUMENTATION \
  -Xswiftc -DSLOPAD_HEIGHT_INDEX_ARRAY \
  SlopadSessionBenchmark \
  --block-counts 100,1000,10000 \
  --iterations 3 \
  --output /tmp/slopad-session-benchmark-array-storage-extended-100-1000-10000-20260706.csv
```

## Added Benchmark Scenarios

- `subtreeDelete`: selects a parent block and deletes it through `EditorSession` input.
  Exercises `EditorModel.removeSubtree` and `BlockLayout` range removal.
- `subtreeReorder`: drags a parent subtree through `EditorSession` pointer input.
  Exercises `EditorModel.moveSubtreeRange` and `BlockLayout` range movement.
- `heightExpansionHitTest`: increases one block's text height, then performs hit-test and
  reveal-style queries. This isolates height update pressure followed immediately by y
  lookup pressure.

For `subtreeDelete` and `subtreeReorder`, benchmark selection starts from the subtree root
block, and the fixture ensures that root owns a visible subtree range. The actual number
of removed/moved blocks is:

| Total block count | Selected subtree node count |
| ----------------: | --------------------------: |
|               100 |                           6 |
|              1000 |                          50 |
|             10000 |                         200 |

## Key Results

The checked-in comparison includes `100`, `1000`, and `10000` blocks. `deltaPct` is
`arrayTotalMs - rbtreeTotalMs`. Negative means array storage is faster; positive means
RBTree storage is faster.

| Block count | Actions won by array | Actions won by RBTree | Ties   |
| ----------: | -------------------: | --------------------: | -----: |
|         100 |              10 / 15 |                4 / 15 | 1 / 15 |
|        1000 |               7 / 15 |                8 / 15 | 0 / 15 |
|       10000 |               6 / 15 |                8 / 15 | 1 / 15 |

Representative actions:

| Action                   | Block count | RBTree total ms | Array total ms | Delta pct | Judgment             |
| ------------------------ | ----------: | --------------: | -------------: | --------: | -------------------- |
| `initialRender`          |         100 |           0.410 |          0.536 |      30.7 | RBTree faster        |
| `initialRender`          |        1000 |           1.272 |          1.104 |     -13.2 | Array faster         |
| `initialRender`          |       10000 |           9.464 |          7.562 |     -20.1 | Array faster         |
| `widthChange`            |         100 |           0.502 |          0.461 |      -8.2 | Array faster         |
| `widthChange`            |        1000 |           1.246 |          0.955 |     -23.4 | Array faster         |
| `widthChange`            |       10000 |          10.820 |          8.032 |     -25.8 | Array faster         |
| `styleRevisionChange`    |         100 |           0.476 |          0.461 |      -3.2 | Array faster         |
| `styleRevisionChange`    |        1000 |           1.219 |          0.932 |     -23.5 | Array faster         |
| `styleRevisionChange`    |       10000 |          10.757 |          8.091 |     -24.8 | Array faster         |
| `heightExpansionHitTest` |         100 |           0.182 |          0.181 |      -0.5 | Similar              |
| `heightExpansionHitTest` |        1000 |           0.153 |          0.177 |      15.7 | RBTree faster        |
| `heightExpansionHitTest` |       10000 |           1.071 |          0.512 |     -52.2 | Array faster         |
| `subtreeDelete`          |         100 |           0.123 |          0.108 |     -12.2 | Array faster         |
| `subtreeDelete`          |        1000 |           0.499 |          1.233 |     147.1 | RBTree much faster   |
| `subtreeDelete`          |       10000 |           2.941 |         46.112 |    1467.9 | RBTree much faster   |
| `subtreeReorder`         |         100 |           0.150 |          0.139 |      -7.3 | Array faster         |
| `subtreeReorder`         |        1000 |           0.674 |          2.134 |     216.6 | RBTree much faster   |
| `subtreeReorder`         |       10000 |           4.337 |         89.974 |    1974.6 | RBTree much faster   |

## Interpretation

Array storage is simple and fast for work that can treat the height index as a flat
ordered sequence:

- full/lazy initial layout
- width/style relayout
- prefix lookup after a height update

RBTree storage wins the decisive cases where a middle range changes, especially when the
document is at least medium-sized:

- subtree removal
- subtree reorder
- repeated structural edits that force array index-map rewrites

At 100 blocks, many array wins are sub-millisecond and do not justify switching the
default to array. At 1000 and 10000 blocks, subtree delete/reorder creates the clearest
difference. The array implementation is doing straightforward array work, but that means
middle splices force tail index rewrites. The cost is small in small documents and rises
quickly afterward.

| Action                                 | 100 blocks | 1000 blocks | 10000 blocks |
| -------------------------------------- | ---------: | ----------: | -----------: |
| `subtreeDelete` array delta vs RBTree  |     -12.2% |     +147.1% |     +1467.9% |
| `subtreeReorder` array delta vs RBTree |      -7.3% |     +216.6% |     +1974.6% |

The RBTree implementation is more complex, but it avoids the same tail-rewrite profile in
structural edits and keeps mutation paths bounded enough to use as the engine default.

The array results are not enough to remove `PrefixSumRedBlackTree`. Important
block-editor cases are not display/read paths only. Subtree deletion and movement create
real middle-range mutation pressure.

## Decision

The default `BlockHeightIndexStorage` implementation is RBTree.

Keep the private array implementation only as an experimental compile-time
implementation. Any future hybrid should preserve the existing `BlockHeightIndexStorage`
surface and prove which workload each storage mode owns.

- array-like storage for full rebuild/read-mostly snapshots
- RBTree-like storage for structural-mutation-heavy snapshots

Do not expose storage selection through `EditorSession`, `SlopadEditorCoreModel`, or
host-facing API.

## AppKit UI Follow-Up Measurement

After this storage experiment, the AppKit/TextKit2 reference host was measured with the
same block counts: `100`, `1000`, and `10000`. See
`APPKIT_UI_BENCHMARK_RESULTS.md` and the `appkit-ui-*-20260706.csv` baselines for UI
frame-budget evidence.

The UI follow-up does not change the storage decision in this document. It verifies that
the default RBTree build is responsive in the measured non-subtree AppKit scenarios, and
that subtree delete/reorder pressure is visible in the real host frame path. The storage
default is still based on the session benchmark and structural mutation results above.

## Verification

```sh
swift test --quiet
swift test -Xswiftc -DSLOPAD_HEIGHT_INDEX_ARRAY --quiet
swift build --product SlopadDebugApp --quiet
swift build --product SlopadUIBenchmarkApp --quiet
swift build --target SlopadHeightBenchmark --quiet
swift build -c release -Xswiftc -DSLOPAD_HEIGHT_INDEX_ARRAY --target SlopadHeightBenchmark --quiet
swift build -c release -Xswiftc -DSLOPAD_TREE_METRICS --target SlopadHeightBenchmark --quiet
swift build -c release -Xswiftc -DSLOPAD_BENCHMARK_INSTRUMENTATION --target SlopadSessionBenchmark --quiet
git diff --check
```
