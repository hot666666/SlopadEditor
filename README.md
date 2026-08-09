<p align="center">
  <img src="Resources/Icon.png" alt="Slopad icon" width="300" height="300">
</p>

<h1 align="center">Slopad</h1>

<p align="center">
  A headless native block editor engine for Swift, with a production AppKit/TextKit2 path.
</p>

<p align="center">
  <img alt="Status: WIP" src="https://img.shields.io/badge/status-WIP-f59e0b">
  <img alt="Swift 6.2+" src="https://img.shields.io/badge/Swift-6.2%2B-f05138">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-2563eb">
</p>

Slopad is a work-in-progress block editor project. Its reusable foundation is
`SlopadEngine`: the canonical document is a tree of blocks, the engine owns editing
meaning, and platform adapters own native input, drawing, focus, and scrolling.

The production platform path is macOS 14+ through AppKit and TextKit2. Package resolution
requires Swift 6.2 or later because the opt-in `SlopadMarkdown` product pins
`swift-markdown` 0.8.0.

## Start Here

Ordinary macOS hosts should depend on the curated facade:

```swift
.product(name: "SlopadAppKit", package: "Slopad")
```

```swift
import SlopadAppKit
```

`SlopadAppKit` is a compile-time facade. It exposes the supported controller, actions,
style, block chrome, snapshots, and document transaction vocabulary, but creates no second
runtime or state owner. `SlopadAppKitUI`, `SlopadAppKitTextKit`, and `SlopadEngine` remain
available to hosts that intentionally build a complete custom adapter.

SwiftUI hosts use the separate `SlopadSwiftUI` product. It layers declarative lifecycle
and observable host state over the same AppKit runtime; it does not create a second editor
or expose the underlying controller.

Run the reference host:

```sh
swift run SlopadDebugApp
```

<img src="Resources/demo.gif" alt="Slopad debug demo" width="720">

## Architecture at a Glance

| Target | Owns | Must not own |
| --- | --- | --- |
| `SlopadEditorModel` | Canonical block tree, selection, commands, transactions, history | Layout, viewport, native state |
| `SlopadBlockLayout` | Visible order, block geometry, hit/reveal facts, height index, text-layout cache | Canonical mutation, platform callbacks |
| `SlopadEngine` | `EditorSession`, composition lifecycle/runtime state, owner coordination, snapshots | Duplicate document or layout state |
| `SlopadAppKitTextKit` | Coherent TextKit2 measurement, geometry, navigation, deletion, attributed content | Editing semantics, native input host |
| `SlopadAppKitUI` | AppKit callback translation, drawing, focus, scrolling, surface synchronization | Canonical mutation or command meaning |
| `SlopadAppKit` | Curated ordinary-host API | Runtime state |
| `SlopadSwiftUI` | SwiftUI mounting, identity, focus, observation, lifecycle flush | A second controller or Session |
| `SlopadMarkdown` | Explicit stateless whole-document decode/encode | Canonical storage, editor runtime |

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
changes. Read `documentSnapshot` on demand to obtain the complete current canonical tree
in parent-before-child depth-first order. It excludes selection, viewport, layout, scroll,
marked-range, and composition-lifecycle metadata. Marked-text callbacks mutate the
snapshot's canonical blocks live, while its revision and the host persistence notification
remain at the last committed value until composition commit. Persist from a committed
update or flush composition first. `visibleBlocks` is never a persistence source, and the
revision is only monotonic within one Session.

### Reviewable document replacement

External assistants and review UIs use `documentContextSnapshot()` followed by
`applyDocumentPatch(_:)`. The context carries an opaque source bound to the exact Session,
committed revision, and selection. The patch is a complete canonical post-image; stale
sources are rejected, and both context capture and patch apply remain unavailable during
active composition. A changed patch commits as one model
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
.product(name: "SlopadMarkdown", package: "Slopad")
```

```swift
import SlopadMarkdown

let blocks = try SlopadMarkdown.decode("# Imported")
let markdown = try SlopadMarkdown.encode(blocks)
```

Decode and encode are synchronous, stateless, and fail closed with typed diagnostics; no
partial document or output is returned. Supported round-trips preserve tree/content
semantics but decode creates fresh `BlockID`s.

Typed Markdown shortcuts are a different path. The internal parser-free
`SlopadMarkdownInputRules` target supplies bounded prefix and inline pattern data, while
`SlopadEditorModel` owns trigger gating, canonical application, and undo semantics.

## Development Surfaces

- `SlopadDebugApp` — reference AppKit host for input, focus, selection, IME, scrolling,
  hit testing, and rendering.
- `SlopadUIBenchmarkApp` — real AppKit interaction and frame-time harness.
- `SlopadHeightBenchmark` and `SlopadSessionBenchmark` — focused non-product benchmarks.
- `Fixtures/DownstreamAppKitHost`, `Fixtures/DownstreamSwiftUIHost`, and
  `Fixtures/DownstreamMarkdownHost` — compile-only proofs of intended public APIs without
  `@testable` or package access.

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
