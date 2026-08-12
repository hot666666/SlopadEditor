<p align="center">
  <img src="Resources/Icon.png" alt="SlopadEditor icon" width="300" height="300">
</p>

<h1 align="center">SlopadEditor</h1>

<p align="center">
  A headless native block editor engine for Swift, with a production AppKit/TextKit2 path.
</p>

<p align="center">
  <img alt="Status: WIP" src="https://img.shields.io/badge/status-WIP-f59e0b">
  <img alt="Swift 6.2+" src="https://img.shields.io/badge/Swift-6.2%2B-f05138">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-2563eb">
</p>

SlopadEditor is a work-in-progress block editor project. Its reusable foundation is
`SlopadEngine`: the canonical document is a tree of blocks, the engine owns editing
meaning, and platform adapters own native input, drawing, focus, and scrolling.

The production platform path is macOS 14+ through AppKit and TextKit2. Package resolution
requires Swift 6.2 or later because the opt-in `SlopadEditorMarkdown` product pins
`swift-markdown` 0.8.0.

## Start Here

Ordinary macOS hosts should depend on the curated facade:

```swift
.product(name: "SlopadEditorAppKit", package: "SlopadEditor")
```

```swift
import SlopadEditorAppKit
```

`SlopadEditorAppKit` is a compile-time facade. It exposes the supported controller, actions,
style, block chrome, snapshots, and document transaction vocabulary, but creates no second
runtime or state owner. `SlopadEditorAppKitUI`, `SlopadEditorAppKitTextKit`, and `SlopadEngine` remain
available to hosts that intentionally build a complete custom adapter.

SwiftUI hosts use the separate `SlopadEditorSwiftUI` product. It layers declarative lifecycle
and observable host state over the same AppKit runtime; it does not create a second editor
or expose the underlying controller.

Run the reference host:

```sh
swift run SlopadDebugApp
```

<img src="Resources/demo.gif" alt="SlopadEditor debug demo" width="720">

## Architecture at a Glance

| Target | Owns | Must not own |
| --- | --- | --- |
| `SlopadEditorDocumentModel` | Canonical block tree, selection, commands, transactions, history | Layout, viewport, native state |
| `SlopadEditorBlockLayout` | Visible order, block geometry, hit/reveal facts, height index, text-layout cache | Canonical mutation, platform callbacks |
| `SlopadEngine` | `EditorSession`, composition/runtime overlays, owner coordination, snapshots | Duplicate document or layout state |
| `SlopadEditorAppKitTextKit` | Coherent TextKit2 measurement, geometry, navigation, deletion, attributed content | Editing semantics, native input host |
| `SlopadEditorAppKitUI` | AppKit callback translation, drawing, focus, scrolling, surface synchronization | Canonical mutation or command meaning |
| `SlopadEditorAppKit` | Curated ordinary-host API | Runtime state |
| `SlopadEditorSwiftUI` | SwiftUI mounting, identity, focus, observation, lifecycle flush | A second controller or Session |
| `SlopadEditorMarkdown` | Explicit stateless whole-document decode/encode | Canonical storage, editor runtime |
| `SlopadEditorArchive` | Versioned native archive encode/decode over canonical blocks | Storage lifecycle, editor runtime |

The compiler-enforced graph is in [`Package.swift`](Package.swift). The
[interactive responsibility map](docs/slopad-architecture-map.html) shows module
relationships, input trajectories, state lifetimes, TextKit boundaries, and host surfaces.
[Architecture](docs/ARCHITECTURE.md) is the text reference for the same contracts and the
rules used to evolve them.

The central rule is simple: one meaning has one authority. Canonical state, runtime
overlays, derived geometry, and host projections have different lifetimes and cannot
substitute for each other.

## Host Contracts

### Persistence

`EditorUpdate.committedDocumentRevision` advances only for committed content or structure
changes. Read `documentSnapshot` on demand to persist the complete canonical tree in
parent-before-child depth-first order. It excludes selection, viewport, layout, scroll,
and live IME composition. `visibleBlocks` is never a persistence source, and the revision
is only monotonic within one Session.

### Reviewable document replacement

External assistants and review UIs use `documentContextSnapshot()` followed by
`applyDocumentPatch(_:)`. The context carries an opaque source bound to the exact Session,
committed revision, and selection. The patch is a complete canonical post-image; stale
sources and active composition are rejected. A changed patch commits as one model
transaction and one undo step, while an exact no-op creates no history or revision.

### AppKit synchronization

Ordinary programmatic edits use `perform(_:)` with `AppKitEditorAction`. The controller
supplies viewport facts and converges the Session snapshot, canvas, native selection,
focus, scroll, and observers before returning. `commitActiveComposition()` is the explicit
save/switch/close lifecycle flush. Hosts customize text presentation through
`AppKitEditorStyle` and block decoration through `AppKitBlockChromeRenderer`; replacing the
native text pipeline requires a complete custom adapter/backend pair.

## Markdown

Markdown is an input/output format, never the canonical model. Whole-document conversion
is opt-in:

```swift
.product(name: "SlopadEditorMarkdown", package: "SlopadEditor")
```

```swift
import SlopadEditorMarkdown

let blocks = try SlopadEditorMarkdown.decode("# Imported")
let markdown = try SlopadEditorMarkdown.encode(blocks)
```

Decode and encode are synchronous, stateless, and fail closed with typed diagnostics; no
partial document or output is returned. Supported round-trips preserve tree/content
semantics but decode creates fresh `BlockID`s.

Typed Markdown shortcuts are a different path. The internal parser-free
`SlopadEditorMarkdownInputRules` target supplies bounded prefix and inline pattern data, while
`SlopadEditorDocumentModel` owns trigger gating, canonical application, and undo semantics.

## Native Archive

Identity-preserving native persistence conversion is a separate opt-in product:

```swift
.product(name: "SlopadEditorArchive", package: "SlopadEditor")
```

```swift
import Foundation
import SlopadEditorArchive

let data = try SlopadEditorArchive.encode(snapshot.blocks)
let blocks = try SlopadEditorArchive.decode(data)
```

The synchronous codec preserves canonical block IDs, tree preorder, kinds, content, and
inline marks. It validates strict UTF-8 JSON, applies bounded V1 wire-admission budgets,
and fails closed with typed errors. These allocation-safety limits are not performance
thresholds or general document-size guidance. The host
still owns snapshot timing, files or databases, debounce, atomic writes, conflicts,
retries, and recovery; archive data contains no selection, history, Session revision,
composition, layout, viewport, TextKit, or storage metadata.

## Development Surfaces

- `SlopadDebugApp` — reference AppKit host for input, focus, selection, IME, scrolling,
  hit testing, and rendering.
- `SlopadUIBenchmarkApp` — real AppKit interaction and frame-time harness.
- `SlopadHeightBenchmark` and `SlopadSessionBenchmark` — focused non-product benchmarks.
- `Fixtures/DownstreamAppKitHost` and `Fixtures/DownstreamSwiftUIHost` — deterministic
  public lifecycle runtime smokes without `@testable` or package access; run both with
  `bash scripts/verify-host-surface.sh`.
- `Fixtures/DownstreamMarkdownHost` — separate opt-in Markdown format-consumer fixture,
  not an ordinary host lifecycle substitute.
- `Fixtures/DownstreamArchiveHost` — isolated codec-surface and AppKit lifecycle probes;
  run both with `bash scripts/verify-archive-surface.sh`.

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — current ownership, state, runtime, and host
  contracts.
- [Architecture map](docs/slopad-architecture-map.html) — interactive projection of those
  relationships and concrete input paths.
- [Roadmap](docs/ROADMAP.md) — only unfinished direction, priorities, and exit criteria.
- [ADRs](ADR/README.md) — durable decisions and their consequences.
- [Testing](docs/TESTING.md) — gate selection and validation provenance.
- [Lessons learned](docs/LESSONS_LEARNED.md) — repeated structural failure patterns.
- [Epic #23 status](docs/epic-23-status.html) — historical completion evidence, not a
  current work queue.

## Development Checks

The baseline for executable changes is:

```sh
swift test --quiet
git diff --check
```

Select additional product, fixture, UI, and benchmark gates from
[`docs/TESTING.md`](docs/TESTING.md). Documentation-only changes require link/path review
and `git diff --check`; do not report executable proof that was not run.
