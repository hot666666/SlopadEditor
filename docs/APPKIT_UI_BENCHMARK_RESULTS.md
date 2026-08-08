# AppKit UI Benchmark Results

Date: 2026-07-06

## Scope

This document records UI benchmark results using `SlopadUIBenchmarkApp` as the real
AppKit reference host.

This is not an engine-only benchmark. Each measured frame includes the host path:

- AppKit scroll/input/pointer preparation for each scenario.
- `EditorSession` input handling when the scenario mutates editor state.
- `renderAndSyncSurface`: `EditorSession.render`, layout, visible block snapshot
  creation, canvas sizing, active native input sync, and dirty rect invalidation.
- Forced AppKit display flushing through `displayIfNeeded`, so `draw(_:)` and TextKit2
  drawing cost are included.

The storage implementation decision belongs to `HEIGHT_INDEX_STORAGE_EXPERIMENT.md`. This
document only records how that cost appears in the AppKit host frame path.

## Frame Pipeline

```mermaid
flowchart LR
    Scenario["scenario preparation<br/>scroll/input/pointer"]
    Operation["EditorSession.handleInput<br/>avgOperationMs"]
    RenderSync["renderAndSyncSurface<br/>avgRenderAndSyncMs"]
    Render["EditorSession.render"]
    Layout["BlockLayout<br/>height index + visible range<br/>TextLayout cache"]
    TextBackend["SlopadAppKitTextKit<br/>TextKit2 fragment layout + geometry"]
    Snapshot["EditorSessionSnapshot<br/>visible blocks + geometry"]
    Surface["canvas resize<br/>active input sync<br/>setNeedsDisplay"]
    Display["displayIfNeeded<br/>avgDisplayMs"]
    Draw["draw(_:)<br/>avgDrawMs"]
    Chrome["host block chrome hook"]
    TextDraw["adapter-owned<br/>TextKit2 fragment drawing<br/>effective live composition included"]
    Decoration["adapter-owned<br/>text selection + caret"]

    Scenario --> Operation --> RenderSync
    RenderSync --> Render --> Layout --> Snapshot --> Surface
    Layout -->|"BlockTextLayoutProtocol"| TextBackend
    Surface --> Display --> Draw --> Chrome --> TextDraw --> Decoration
```

`scroll` is special. The benchmark changes scroll position before the timed frame. Read
`scroll` numbers as the cost to render/draw the new viewport, not as native scroll event
handling cost.

## Metrics

| Metric               | Meaning                                                                                                                                       |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `avgFPS`             | `1000 / avgFrameMs`. Average throughput; higher is better.                                                                                    |
| `avgFrameMs`         | Average total measured frame time. Includes operation, render/sync, display, draw, and small harness overhead.                               |
| `p95FrameMs`         | 95th percentile of total frame time. More important than `avgFPS` for quickly spotting visible stutter.                                      |
| `avgOperationMs`     | Scenario operation time before render/sync. Native insert, composition update, block selection, and block reorder land here.                 |
| `avgRenderAndSyncMs` | Engine render and host surface sync time through `renderAndSyncSurface`.                                                                      |
| `avgDisplayMs`       | Time spent forcing an AppKit display flush.                                                                                                  |
| `avgDrawMs`          | Time spent inside the canvas draw callback.                                                                                                  |
| `over16ms`           | Number of frames whose total `frameMs` exceeded 16.67ms.                                                                                     |
| `over33ms`           | Number of frames whose total `frameMs` exceeded 33.33ms.                                                                                     |
| `heightIndex*Count`  | Height-index operation counts recorded by benchmark instrumentation, including rebuild, insert, remove, move, and height update operations. |

In the frame-budget tables below, the 16.67ms threshold is always based on total
`frameMs`, not render/sync time alone.

## Baseline Files

- `Benchmarks/Baselines/appkit-ui-rbtree-20260706.csv`: raw frame samples using the
  default `RBTreeBlockHeightIndexStorage`.
- `Benchmarks/Baselines/appkit-ui-array-20260706.csv`: raw frame samples built with
  `-Xswiftc -DSLOPAD_HEIGHT_INDEX_ARRAY`.
- `Benchmarks/Baselines/appkit-ui-summary-20260706.csv`: aggregate metrics by storage,
  scenario, and block count.
- `Benchmarks/Baselines/appkit-ui-storage-compare-20260706.csv`: side-by-side AppKit UI
  frame comparison.
- `Benchmarks/Baselines/appkit-ui-subtree-rbtree-20260706.csv`: raw subtree samples using
  the default `RBTreeBlockHeightIndexStorage`.
- `Benchmarks/Baselines/appkit-ui-subtree-array-20260706.csv`: raw subtree samples built
  with `-Xswiftc -DSLOPAD_HEIGHT_INDEX_ARRAY`.
- `Benchmarks/Baselines/appkit-ui-subtree-summary-20260706.csv`: aggregate metrics for
  subtree UI scenarios.
- `Benchmarks/Baselines/appkit-ui-subtree-storage-compare-20260706.csv`: subtree UI
  side-by-side comparison.
- `Benchmarks/Baselines/appkit-unicode-navigation-summary-20260717.csv`: document-size
  and active-text-length sweeps for mixed-script TextKit navigation.

Each scenario ran 60 measured frames at block counts `100`, `1000`, and `10000`.

## Scenarios

- `scroll`: changes viewport position from top to bottom, then renders/displays the new
  viewport.
- `native-insert`: sends text insertion through the active native input path.
- `composition`: updates the active block's live composition overlay.
- `height-expansion`: inserts text so one block wraps, grows in height, and pushes
  downstream y positions.
- `block-selection`: selects a block through the gutter pointer path.
- `block-reorder`: drags the selected single block near adjacent visible blocks.
- `mixed`: cycles through scroll, insert, composition, block selection, height expansion,
  and block reorder.
- `subtree-delete`: builds a tree fixture, selects a visible subtree range, then deletes
  it. Because deletion is destructive, the document is reset before each measured frame.
- `subtree-reorder`: uses the same tree fixture, selects a visible subtree range, then
  drags it near an outside block.
- `style-change`: alternates geometry-affecting editor styles through the synchronized
  public AppKit action.
- `unicode-navigation`: alternates backend-resolved native word-left/word-right movement
  in mixed Korean, English, Hebrew, emoji, and combining-mark text.

Subtree scenarios use the same subtree-size rule as the session benchmark.

| Total block count | Selected/changed subtree node count |
| ----------------: | -----------------------------------: |
|               100 |                                    6 |
|              1000 |                                   50 |
|             10000 |                                  200 |

## Commands

Default RBTree storage:

```sh
swift run -c release -Xswiftc -DSLOPAD_BENCHMARK_INSTRUMENTATION \
  SlopadUIBenchmarkApp \
  --output /tmp/slopad-ui-bench-20260706/rbtree-scroll-10000.csv \
  --block-count 10000 \
  --frames 60 \
  --scenario scroll
```

Array storage comparison build:

```sh
swift run -c release \
  -Xswiftc -DSLOPAD_BENCHMARK_INSTRUMENTATION \
  -Xswiftc -DSLOPAD_HEIGHT_INDEX_ARRAY \
  SlopadUIBenchmarkApp \
  --output /tmp/slopad-ui-bench-20260706/array-scroll-10000.csv \
  --block-count 10000 \
  --frames 60 \
  --scenario scroll
```

The full sweep used the same command shape for these combinations:

```text
scenarios: scroll,native-insert,composition,height-expansion,block-selection,block-reorder,mixed
blockCounts: 100,1000,10000
frames: 60
storages: default RBTree, SLOPAD_HEIGHT_INDEX_ARRAY
```

The subtree follow-up used these combinations:

```text
scenarios: subtree-delete,subtree-reorder
blockCounts: 100,1000,10000
frames: 60
storages: default RBTree, SLOPAD_HEIGHT_INDEX_ARRAY
```

Pass `--subtree-node-count N` to inspect subtree-size sensitivity within a fixed document
size.

## Runtime Style Replacement Follow-up

Date: 2026-07-17

Environment: macOS 27.0 (26A5378n), Xcode 27.0 (27A5194q), arm64, release build

The `style-change` scenario alternates two geometry-affecting `TextKitEditorStyle` values
through the public `updateEditorStyle(_:)` action on every measured frame. The timed
operation includes construction of the coherent TextKit layout/render/decoration pipeline,
engine backend replacement, cache invalidation, and the action's synchronized render. The
normal runner render immediately afterward is warm, which is why its separate
`avgRenderAndSyncMs` is close to zero.

| Blocks | Avg operation | Avg frame | P95 frame | Frames >16.67ms | Frames >33.33ms |
| -----: | ------------: | --------: | --------: | ---------------: | ---------------: |
|    100 |       7.311ms |  16.749ms |  17.327ms |          33 / 60 |           0 / 60 |
|   1000 |       4.130ms |  14.085ms |  14.554ms |           0 / 60 |           0 / 60 |
|  10000 |      14.643ms |  24.867ms |  25.506ms |          60 / 60 |           0 / 60 |

This cost is paid only when a different style is installed; ordinary input, layout, and
drawing hot paths do not gain a new lock or dynamic backend lookup, and reinstalling an
equal style is a no-op. At 10,000 blocks the contract is appropriate for infrequent editor
settings or theme changes, not per-frame font/spacing animation. A future paint-only
appearance contract should avoid text-layout replacement entirely.

The checked-in aggregate is
`Benchmarks/Baselines/appkit-runtime-style-summary-20260717.csv`.

## Unicode Navigation Follow-up

Date: 2026-07-17

Environment: macOS 27.0 (26A5378n), Xcode 27.0 (27A5194q), arm64, release build

The `unicode-navigation` scenario alternates native word-left and word-right near the end
of a mixed-script paragraph. The operation measurement includes Session routing,
grapheme/UTF-16 conversion, TextKit2 linguistic navigation, result validation, and
selection application. Identical request/style preparation is memoized, so steady-state
movement does not rebuild the attributed storage or force full text layout on every key.
Grapheme/UTF-16 boundary maps are also created lazily for the prepared request and reused
for constant-time conversion after the cold operation.

Document-size sweep with the default short mixed-script paragraph:

| Blocks | Avg operation | Median operation | P95 operation | Cold first operation |
| -----: | ------------: | ---------------: | ------------: | -------------------: |
|    100 |       0.240ms |          0.198ms |       0.251ms |              3.127ms |
|   1000 |       0.225ms |          0.202ms |       0.238ms |              1.969ms |
|  10000 |       0.225ms |          0.200ms |       0.242ms |              1.868ms |

The steady input cost is effectively independent of total document size in this sweep;
10,000 blocks do not cause document-wide navigation work.

Active-paragraph-length sweep at a fixed 100-block document:

| Graphemes | Avg operation | Median operation | P95 operation | Cold first operation | Avg frame | P95 frame |
| --------: | ------------: | ---------------: | ------------: | -------------------: | --------: | --------: |
|       100 |       0.249ms |          0.210ms |       0.255ms |              2.243ms |  18.648ms |  19.597ms |
|      1000 |       0.376ms |          0.324ms |       0.386ms |              4.037ms |  17.383ms |  18.160ms |
|     10000 |       2.336ms |          1.658ms |       1.774ms |             43.981ms |  66.751ms |  66.844ms |

This is not a zero-cost path. Steady navigation remains below 0.4ms at p95 through 1,000
graphemes and reaches 1.774ms at p95 for 10,000 graphemes. The request-local index map
reduced that 10,000-grapheme p95 from the pre-optimization 5.565ms by about 68%. The cold
first movement still costs 43.981ms because it includes lazy index construction and native
layout work. The same extreme paragraph spends about 61.122ms per frame in TextKit/AppKit
drawing, which dominates its 66.751ms average frame. Cold preparation and long-fragment
drawing therefore remain explicit performance risks even though steady conversion and
ordinary short-block navigation are bounded.

Example long-text command:

```sh
swift run -c release -Xswiftc -DSLOPAD_BENCHMARK_INSTRUMENTATION \
  SlopadUIBenchmarkApp \
  --scenario unicode-navigation \
  --block-count 100 \
  --active-text-length 10000 \
  --frames 60 \
  --output /tmp/slopad-unicode-navigation-10000.csv
```

The checked-in aggregate is
`Benchmarks/Baselines/appkit-unicode-navigation-summary-20260717.csv`.

## Default UI Results

The default build uses `RBTreeBlockHeightIndexStorage`. Each cell is
`avgFPS / p95FrameMs`: average throughput first, then the 95th percentile of total frame
time.

| Scenario           |      100 blocks |     1000 blocks |    10000 blocks |
| ------------------ | --------------: | --------------: | --------------: |
| `scroll`           | 134.5 / 11.52ms |  136.8 / 8.59ms | 112.9 / 10.96ms |
| `native-insert`    |  156.2 / 7.75ms |  146.8 / 8.03ms | 116.0 / 10.34ms |
| `composition`      |  152.2 / 7.55ms |  159.8 / 6.61ms |  148.3 / 7.25ms |
| `height-expansion` | 130.3 / 10.59ms | 121.8 / 10.85ms | 112.2 / 11.33ms |
| `block-selection`  |  158.0 / 6.85ms |  166.8 / 6.63ms |  171.4 / 6.15ms |
| `block-reorder`    |  159.6 / 6.98ms |  145.9 / 8.03ms |  93.9 / 12.35ms |
| `mixed`            |  159.5 / 7.83ms |  187.2 / 9.02ms | 183.4 / 11.03ms |

At 10000 blocks, every default non-subtree scenario stayed under the 16.67ms frame budget
at p95, and `0 / 60` total frames exceeded 16.67ms.

## 10000-Block Frame Breakdown

This table shows total frame time and the main slices together. Render/sync time and total
frame-budget overrun counts are intentionally separated.

| Storage | Scenario          | avgFrameMs | p95FrameMs | avgOperationMs | avgRenderAndSyncMs | avgDisplayMs | avgDrawMs | Frames over 16.67ms |
| ------- | ----------------- | ---------: | ---------: | -------------: | -----------------: | -----------: | --------: | ------------------: |
| RBTree  | `composition`     |      6.742 |      7.245 |          0.003 |              0.157 |        6.581 |     6.253 |              0 / 60 |
| RBTree  | `native-insert`   |      8.617 |     10.336 |          2.086 |              0.190 |        6.341 |     6.022 |              0 / 60 |
| RBTree  | `block-reorder`   |     10.648 |     12.346 |          1.626 |              2.483 |        6.539 |     6.182 |              0 / 60 |
| RBTree  | `subtree-delete`  |      8.670 |      9.593 |          5.785 |              2.549 |        0.335 |     0.206 |              0 / 60 |
| RBTree  | `subtree-reorder` |     18.824 |     23.615 |          6.543 |              4.290 |        7.991 |     7.555 |             60 / 60 |
| Array   | `subtree-delete`  |     51.148 |     53.966 |          5.266 |             45.625 |        0.256 |     0.164 |             60 / 60 |
| Array   | `subtree-reorder` |    112.534 |    123.011 |          6.649 |             97.055 |        8.829 |     8.332 |             60 / 60 |

Interpretation:

- `composition` is mostly AppKit/TextKit display and drawing cost.
- `native-insert` shows input cost, but display/draw still dominates total frame time.
- Single-block `block-reorder` starts to show render/sync cost, but remains inside budget.
- RBTree `subtree-reorder` has much lower render/sync cost than the array build, but still
  exceeds 16.67ms in this UI host.
- Array subtree mutation is dominated by render/sync because layout consumes many
  height-index remove/move operations after the structural change.

## UI Host Storage Comparison

The 10000-block non-subtree comparison is based on average total frame time. `Delta frame
pct` is `arrayAvgFrameMs - rbtreeAvgFrameMs`. Negative means the array build has lower
average frame time; positive means the RBTree build has lower average frame time.

| Scenario           | RBTree avgFPS | Array avgFPS | Delta frame pct | UI result      |
| ------------------ | ------------: | -----------: | --------------: | -------------- |
| `scroll`           |         112.9 |        121.2 |           -6.8% | array faster   |
| `native-insert`    |         116.0 |        132.1 |          -12.1% | array faster   |
| `composition`      |         148.3 |        150.2 |           -1.3% | similar        |
| `height-expansion` |         112.2 |         97.2 |           15.4% | RBTree faster  |
| `block-selection`  |         171.4 |        149.8 |           14.5% | RBTree faster  |
| `block-reorder`    |          93.9 |         96.7 |           -2.9% | similar        |
| `mixed`            |         183.4 |        178.5 |            2.7% | similar        |

The non-subtree UI host comparison is mixed. Array is faster in some display/read-heavy
paths; RBTree is faster in height expansion and block selection; several rows are
tie-level. Read this table only as UI frame evidence. The storage decision belongs to
`HEIGHT_INDEX_STORAGE_EXPERIMENT.md`.

At 10000 blocks, subtree work shows storage pressure clearly in the UI path too.

| Scenario          | Storage | avgFrameMs | p95FrameMs | avgRenderAndSyncMs | Frames over 16.67ms |
| ----------------- | ------- | ---------: | ---------: | -----------------: | ------------------: |
| `subtree-delete`  | RBTree  |      8.670 |      9.593 |              2.549 |              0 / 60 |
| `subtree-delete`  | Array   |     51.148 |     53.966 |             45.625 |             60 / 60 |
| `subtree-reorder` | RBTree  |     18.824 |     23.615 |              4.290 |             60 / 60 |
| `subtree-reorder` | Array   |    112.534 |    123.011 |             97.055 |             60 / 60 |

## Interpretation

- The default AppKit UI path is healthy for the measured non-subtree scenarios at 10000
  blocks. Every p95 frame time stays below 16.67ms.
- A large part of ordinary frame time is AppKit/TextKit display and drawing. In this
  sweep, much of `composition`, `block-selection`, and `native-insert` is display/draw
  bound.
- `scroll` stays inside budget at 10000 blocks and updates exact heights for newly exposed
  blocks through lazy measurement.
- Single-block reorder is a useful UI pressure case, but it does not represent large
  structural selections. Subtree delete/reorder are the structural UI cases.
- The AppKit UI sweep should be read together with `HEIGHT_INDEX_STORAGE_EXPERIMENT.md`,
  but it does not own the storage default decision. This document records only what was
  visible in the reference host frame path.

## Prepared Layout Store Policy (#37)

Date: 2026-08-08

Measured source: `a8c05f7fd75e3bcec326505129b042a86291fe3c` on
`codex/b4-bounded-prepared-store` (`e3541be` contains the prepared-store production
implementation; the measured HEAD also includes the Epic #23 integration). Environment:
macOS 26.5.2, Xcode 26.5 (17F42), arm64, 920x680 window, release build with
`SLOPAD_BENCHMARK_INSTRUMENTATION`.

The control is the same measured source with `entryLimit=1`. It isolates store capacity
while keeping the harness, draw-inclusive counter boundary, and production code otherwise
identical. It is a **same-head control**, not the historical exact `6811793` baseline and
must not be described as one. Raw frame CSVs remain local; the compact checked-in aggregate
is `Benchmarks/Baselines/appkit-prepared-layout-store-summary-20260808.csv`.

Representative command shape:

```sh
swift run -c release -Xswiftc -DSLOPAD_BENCHMARK_INSTRUMENTATION \
  SlopadUIBenchmarkApp \
  --scenario forward-reverse-scroll \
  --block-count 10000 \
  --frames 128 \
  --prepared-entry-limit 96 \
  --prepared-cost-limit 6291456 \
  --output /tmp/slopad-prepared-forward-96-6m.csv
```

The count sweep used an 8 MiB cost cap. Its initial grid was
`1, 8, 16, 24, 32, 48, 64`; the knee search then extended it with
`80, 96, 112, 128`. Values below are medians of three 10,000-block
`forward-reverse-scroll` repetitions.

| Entry limit | Hit ratio | Prepares | Resident estimate | P95 frame |
| ----------: | --------: | -------: | ----------------: | --------: |
|          64 |     0.759 |      647 |          4.03 MiB |   5.395ms |
|          80 |     0.870 |      348 |          5.03 MiB |   5.466ms |
|          96 |     0.965 |       93 |          6.04 MiB |   5.119ms |
|         112 |     0.971 |       77 |          6.54 MiB |   4.821ms |
|         128 |     0.971 |       77 |          6.54 MiB |   4.859ms |

`96` is the smallest count knee. Moving to `112` improves hit ratio by only 0.6
percentage points and removes 16 prepares; its p95 difference is below the precommitted
8% resolution threshold. `128` adds no reuse.

The cost sweep fixed the entry limit at 96:

| Cost limit | Hit ratio | Prepares | Resident estimate | P95 frame |
| ---------: | --------: | -------: | ----------------: | --------: |
|      4 MiB |     0.759 |      647 |                 - |   5.451ms |
|      5 MiB |     0.844 |      418 |                 - |   4.957ms |
|      6 MiB |     0.924 |      205 |         5.978 MiB |   4.748ms |
|      7 MiB |     0.965 |       93 |          6.04 MiB |   4.763ms |
|      8 MiB |     0.965 |       93 |          6.04 MiB |   4.763ms |

The checked-in aggregate's 6-to-7 MiB gain is 4.1 percentage points, below the 5-point knee rule, while p95 is
tied. A five-repetition repeated-viewport follow-up differed by more than 8%, but 7 MiB
was faster in only three of five runs and therefore failed the precommitted four-of-five
direction rule. The selected production default is **96 entries / 6 MiB estimated cost**.

### Same-head control versus selected policy at 10,000 blocks

Medians use three repetitions except `repeated-viewport`, which uses five.

| Scenario | P95 frame control -> selected | Hit ratio control -> selected | Prepares control -> selected | Notes |
| --- | ---: | ---: | ---: | --- |
| `repeated-viewport` | 5.140 -> 4.353ms | 0.056 -> 1.000 | 1020 -> 0 | same viewport reuse |
| `forward-reverse-scroll` | 5.981 -> 4.748ms | 0.003 -> 0.924 | 2677 -> 205 | bounded overlapping locality |
| `native-insert` | 8.384 -> 6.540ms | 0.091 -> 0.955 | 1200 -> 60 | operation p95 2.331 -> 1.820ms |
| `composition` | 5.410 -> 4.237ms | 0.055 -> 0.953 | 1200 -> 60 | live composition path |
| `text-selection-drag` | 7.056 -> 5.493ms | 0.456 -> 1.000 | 1143 -> 0 | real mouse down/drag/up path |
| `pressure-recovery` | 6.333 -> 5.341ms | - | 1050 -> 1050 | footprint 47.64 -> 48.58 MiB; over-budget contexts 0 |
| `long-active-paragraph` | 169.879 -> 172.730ms | - | 540 -> 60 | footprint 390.78 -> 385.97 MiB; over-budget contexts 0 |

One-run correctness sweeps passed at 100, 1,000, and 10,000 blocks for cold first
layout, repeated viewport, local forward/reverse scroll, native insertion, composition,
real text-selection drag, width resize, style replacement, and whole-document scroll.
The apparent 100-block width result was repeated five times: control p95 was about
9.468ms and selected p95 about 9.499ms, a tie. At 10,000 blocks, key scenarios stayed
under 16.67ms except cold layout, width/style replacement, and the extreme 16K active
paragraph; those paths were already slow in the same-head control and the selected policy
did not materially regress them.

The cost metric is an estimate for retained TextKit graphs, not an allocator-reported byte
count. Process footprint is noisy at sub-MiB scale, three-repetition medians do not resolve
small differences, and changes below the stated 8% or direction thresholds are treated as
ties. Pressure recovery intentionally re-prepares after eviction, so equal prepare counts
there are expected; the important checks are bounded residency and zero over-budget
contexts.
