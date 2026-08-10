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

### Installed-input-method diagnostic trace

For an actual Apple Korean 2-set session, build and launch the debug host with an exact
checkout identity and the opt-in native-input trace:

```sh
test -z "$(git status --short)"
SLOPAD_BUILD_STATE=clean SLOPAD_BUILD_SHA="$(git rev-parse HEAD)" \
  swift run SlopadDebugApp --native-input-trace \
  2> /tmp/slopad-native-input-trace.log
rg '^SLOPAD_NATIVE_INPUT_TRACE ' /tmp/slopad-native-input-trace.log
```

`SLOPAD_BUILD_SHA` is a caller-declared checkout HEAD, not a binary identity discovered by
the app. `sourceState=clean` is valid only after the clean-status command succeeds. When
diagnosing an uncommitted build, pass `SLOPAD_BUILD_STATE=dirty` instead and treat
`declaredHeadSHA` as its base commit, not as an exact identifier for the executable.

The option is disabled by default. Its schema, sink, and event construction compile only in
debug builds; release retains the semantics-neutral inlined owner forwarding helper but no
trace branch or payload. Each prefixed JSON record carries OS and declared source
provenance; native callback records also carry the public
`NSTextInputContext.selectedKeyboardInputSource` identifier when AppKit exposes it. The
trace distinguishes adapter-owned canvas focus transitions, key routing and the before/after
`interpretKeyEvents` boundary, text callbacks and ranges, ActiveInput guard outcomes,
emitted Session event/results, native-surface block-token synchronization, and `firstRect`
request/result availability. Actual `canvasIsFirstResponder` is sampled only on later key
and text callback records, after AppKit has settled responder assignment. Surface-sync
records explicitly report that this diagnostic did not call
`invalidateCharacterCoordinates`; the trace does not change that behavior.

No canonical document text or snapshot is written. Callback/key text is capped at 16
characters with the full UTF-16 length and a truncation flag. Raw `BlockID` values are never
serialized; a process-seeded 16-hex-character `blockToken` correlates records only within
one app run and is intentionally unstable across runs. The log is still sensitive diagnostic
output and should not be retained unnecessarily.

A trace containing direct `setMarkedText` injection remains direct-callback evidence. An
installed-IME claim additionally requires a real physical event and selected input source,
followed by the system-delivered marked update and commit/cancel callbacks in the same
recording. `firstRect` availability records the adapter's candidate anchor answer; it does
not by itself prove that the candidate window appeared or was placed correctly. Record that
UI observation separately. One observed marked update is delivery evidence, not proof of a
complete installed-IME lifecycle or ADR 0014's future live replacement semantics.

On 2026-08-10, OS UI automation sending a key-code sequence while Apple Korean 2-set was
selected produced progressive `insertText` replacements (`ㅎ` → `하` → `한`) rather than
`setMarkedText`. That recording is useful routing evidence only. The keys were synthetic,
so it cannot satisfy the physical installed-IME completion criterion or establish a product
contract for which callback sequence AppKit or the input method will use.

## Swift Testing AppKit window ownership

Test windows must use the target-local `AppKitTestWindow` or `SwiftUITestWindow`. Swift
retains these fixtures with ARC, while a plain programmatic `NSWindow` defaults
`isReleasedWhenClosed` to `true`. Calling `close()` with both policies active releases the
same test-owned window through AppKit's legacy close-release path and again when the Swift
Testing main-actor job drains, which produced signal 11 in `objc_release` after the test body
had returned. The test window types set `isReleasedWhenClosed = false`; this changes fixture
ownership only and does not bypass the production canvas/controller teardown path.

Issue #72 isolated that ownership boundary on macOS 26.5.2 (25F84), Xcode 26.5 (17F42),
Swift 6.3.2, and Swift Testing 1902. A plain `NSWindow` logged body entry, the default
`isReleasedWhenClosed == true`, and body exit before failing with signal 11. The otherwise
identical ARC-owned window passed with the flag set to `false`. Separate first-responder,
standalone `NSTextInsertionIndicator` automatic-to-hidden-and-detach, production canvas,
and production controller probes passed, while the original native callback helper also
logged body exit before failing. This distinguished fixture ownership from production
selection, IME, caret, scroll-observer, or controller teardown semantics.

The fixed minimal regression is:

```sh
swift test --quiet --filter \
  'SlopadAppKitUITests.AppKitTestWindowLifetimeTests/arcOwnedWindowClosesWithoutAppKitRelease'
```

On the environment above it passed in 20 independent `swift test` processes (`20/20`, one
test per run). The canonical combined `swift test --quiet` then passed in five independent
processes (`5/5`, 656 tests in 132 suites per run). These are local test-runner results, not
installed-IME, native product interaction, device, or remote CI evidence.

## Documentation-only changes

Do not run executable tests merely to create a claim for a non-executable change. Instead
run `git diff --check`, verify changed relative links and referenced paths, and validate
the changed artifact's structure. For an interactive HTML status page, check its expected
controls, links, selectors, script references, and narrow responsive layout; use a browser
or screenshot when available and record the limitation when it is not.
