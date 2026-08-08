# Testing and Verification

Choose verification by the owner and change surface. Current source and tests define what
the code does; do not report a build, runtime path, benchmark, or device result that was
not actually run.

## Baseline executable change gate

```sh
swift test --quiet
git diff --check
```

Run focused owner tests while iterating, then the baseline after the executable diff is
stable. `swift test` is not evidence for a host-only runtime path by itself.

## Add the gates the change invalidates

| Change surface | Required additional gate |
| --- | --- |
| AppKit or public host API | `swift build --product SlopadAppKit --quiet`; `swift build --product SlopadAppKitTextKit --quiet`; `swift build --product SlopadAppKitUI --quiet`; `swift build --package-path Fixtures/DownstreamAppKitHost --product DownstreamAppKitHost --quiet` |
| UI or runtime input/rendering | `swift build --product SlopadDebugApp --quiet`; exercise the affected native path in `SlopadDebugApp` when the claim is behavioral rather than compile-only |
| Layout, drawing, cache, frame-time, drag/reorder, or large documents | `swift build --product SlopadUIBenchmarkApp --quiet`; run the affected `SlopadUIBenchmarkApp` scenario and state the benchmark environment and resolution limits |
| Package or target graph | `swift package dump-package` |
| Public SwiftUI host surface | build the downstream SwiftUI fixture and exercise its intended mount → edit → observe → flush → replace → unmount path |
| Markdown format boundary | build the downstream Markdown fixture; verify supported round trips and typed failure diagnostics through the public codec boundary |

For a focused repair, rerun the focused regression and only the broader gate that the
repair invalidated. Do not relabel a unit test as visual, device, remote CI, or benchmark
evidence.

## Documentation-only changes

Do not run executable tests merely to create a claim for a non-executable change. Instead
run `git diff --check`, verify changed relative links and referenced paths, and validate
the changed artifact's structure. For an interactive HTML status page, check its expected
controls, links, selectors, script references, and narrow responsive layout; use a browser
or screenshot when available and record the limitation when it is not.
