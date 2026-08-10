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

## Continuous public host gate

```sh
bash scripts/verify-host-surface.sh
```

`just host-surface` delegates to the same script. This is the canonical continuous ADR
0012 gate on every pull request. It builds and runs both ordinary one-product lifecycle
fixtures: `DownstreamAppKitHost` through `SlopadAppKit` alone and
`DownstreamSwiftUIHost` through `SlopadSwiftUI` alone. Each mounts a literal window/view,
performs a public semantic edit, observes the committed snapshot, flushes composition
before reading, replaces the document with epoch/identity/content checks, exercises
focus/resize, and tears down deterministically.

This proves public lifecycle behavior and downstream source compatibility. It is not a
visual, native key/pointer callback, installed-IME, candidate-window, physical-device, or
accessibility proof. Composition flush may be a no-op in this gate; native callback and
installed input-method delivery require their dedicated AppKit/UI evidence.

## Add the gates the change invalidates

| Change surface | Required additional gate |
| --- | --- |
| AppKit or public host API | `bash scripts/verify-host-surface.sh`; `swift build --product SlopadAppKit --quiet`; `swift build --product SlopadAppKitTextKit --quiet`; `swift build --product SlopadAppKitUI --quiet` |
| UI or runtime input/rendering | `swift build --product SlopadDebugApp --quiet`; exercise the affected native path in `SlopadDebugApp` when the claim is behavioral rather than compile-only |
| Layout, drawing, cache, frame-time, drag/reorder, or large documents | `swift build --product SlopadUIBenchmarkApp --quiet`; run the affected `SlopadUIBenchmarkApp` scenario and state the benchmark environment and resolution limits |
| Package or target graph | `swift package dump-package` |
| Public SwiftUI host surface | `bash scripts/verify-host-surface.sh`; `swift build --product SlopadSwiftUI --quiet` |
| Markdown format boundary | build the downstream Markdown fixture; verify supported round trips and typed failure diagnostics through the public codec boundary |

For a focused repair, rerun the focused regression and only the broader gate that the
repair invalidated. Do not relabel a unit test as visual, device, remote CI, or benchmark
evidence.

## AppKit native callback smoke scope

`AppKitNativeCallbackSmokeTests` mounts the production `AppKitEditorViewController` in an
`NSWindow`. Pointer and keyboard checks enter through synthesized `NSEvent` values delivered
by `NSWindow.sendEvent(_:)`; marked-text checks enter through the canvas's real
`NSTextInputClient` callbacks. The layer complements direct adapter/Session unit tests and
must not call controller semantic handlers as a substitute for native callback coverage.

AppKit has no deterministic test API that asks the user's installed input method server to
compose a specific string. The marked-text smoke therefore reproduces the callback sequence
that AppKit delivers, but it does not prove a physical keyboard, global event routing, input
source selection, candidate-window UI, or a particular third-party IME. Exercise the same
path in `SlopadDebugApp` when the claim depends on those system integrations.

## Documentation-only changes

Do not run executable tests merely to create a claim for a non-executable change. Instead
run `git diff --check`, verify changed relative links and referenced paths, and validate
the changed artifact's structure. For an interactive HTML status page, check its expected
controls, links, selectors, script references, and narrow responsive layout; use a browser
or screenshot when available and record the limitation when it is not.
