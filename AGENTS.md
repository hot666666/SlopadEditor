# AGENTS.md

This file is the entry point for agents working in the Slopad repository. Use
`README.md` for the current structural map, this file for terminology and responsibility
criteria, `ADR/` for durable architecture decisions, and `docs/ROADMAP.md` for the
development direction.

## Project Overview

`SlopadEngine` is a headless native block editor engine written in Swift. It is aimed at
Notion/Craft-style block editor hosts. The document is a block tree, and editor semantics
belong to the engine. Platform code supplies native input, drawing, and text layout
backends.

The current platform path is macOS AppKit + TextKit2. AppKit is an adapter, not the engine
model. `SlopadAppKit` is the recommended ordinary macOS host product/import and curates
the default platform surface. Its `SlopadAppKitUI` component translates AppKit callbacks
into engine input values and applies the layout/render/hit-test/reveal/redraw facts
returned by `EditorSession` through AppKit drawing plus focus/scroll synchronization.

SlopadEngine owns block document state and block identity, caret/text/block selection,
keyboard/pointer/native command/IME composition semantics, command application,
undo/redo, semantic change projection, block layout orchestration, hit testing, reveal
geometry, and render snapshots.

The public persistence projection is `EditorDocumentSnapshot`, not
`EditorSessionSnapshot.visibleBlocks`. `EditorUpdate.committedDocumentRevision` is present
only for a committed canonical mutation. Hosts read the matching complete snapshot on the
Session-owning executor before transferring that `Sendable` value elsewhere. The revision
is scoped to one Session and must not be treated as a database revision.

The review-before-apply projection is `EditorDocumentContextSnapshot`, not a persistence
snapshot. Its opaque source exact-CASes Session epoch, committed revision, and captured
selection. `EditorDocumentPatch` is a canonical full post-image applied as one model
transaction. Active composition must be committed before context capture or apply.

The engine does not own platform widgets. Concrete views such as `NSTextView` or
`UITextView` are not engine targets. A native surface collects OS callbacks, forwards them
as engine input, and draws engine snapshots. `SlopadEngine` decides semantic behavior such
as caret/selection, marked-text lifecycle, insert/delete/native command intent, block
transitions, and shortcut normalization.

Markdown is not the canonical model. The canonical model is a tree-capable block store.
Markdown is only import/export format or input shortcut syntax.

## Document Index

- `README.md`: architecture map, package products, and AppKit platform facade usage.
- `docs/ARCHITECTURE.md`: detailed target graph, runtime ownership flow, platform
  extension boundary, and architecture philosophy.
- `ADR/`: durable architecture decision records.
- `docs/ROADMAP.md`: completed milestones, next product/performance direction, and open
  risks.
- `docs/LOOP_REQUEST_TEMPLATE.md`: copy-paste template for bounded loop requests.
- `docs/LESSONS_LEARNED.md`: past cleanup/refactor failure patterns. It is not the source
  of truth for current structure.
- `Benchmarks/Baselines/README.md`: checked-in CSV baseline index.

Do not treat state-management or cleanup-campaign plan/review/goal/handoff documents as
sources of truth.

## Core Layers

- `SlopadEngine`: UI-facing facade for platform hosts. `EditorSession` receives input,
  live IME/composition overlays, render, hit-test, reveal, and redraw requests, calls
  `EditorModel` and `BlockLayout`, and returns results consumed by UI code.
- `SlopadCoreModel`: public vocabulary interpreted by both hosts and engine layers, plus
  package canonical `Document`/`Block` values. It is not a dump for internal projections
  or generic helpers.
- `SlopadEditorModel`: owns the storable canonical `Document`, `Selection`, `Command`,
  `Transaction`, `History`, semantic `Change`, and validation/atomic application of a
  canonical full document post-image. It must not import
  `SlopadBlockLayout`, and it must not contain live composition, layout, y offsets,
  TextKit rects, or render damage.
- `SlopadBlockLayout`: manages block heights/y positions, visible ranges,
  reveal/hit-test geometry, and layout snapshots. It must not import
  `SlopadEditorModel`; it uses `TextLayout` and `BlockHeightIndexStorage` as internal
  axes.
- `TextLayout`: the axis for the `BlockTextLayoutProtocol` backend seam and layout cache.
  It covers line fragments, caret/selection rects, and text hit-testing, not only height.
  Do not rename it to `textMeasurer`.
- `BlockHeightIndexStorage`: owner of block height/y prefix-sum storage. The default
  implementation uses `PrefixSumRedBlackTree`.
- `SlopadDataStructure`: pure data structures with no editor concepts.
- `SlopadAppKit`: curated facade product/target for ordinary macOS hosts. It re-exposes
  the supported controller, action, style, chrome, document, selection, update, and
  snapshot vocabulary for the default AppKit + TextKit2 stack. It is not a new runtime or
  semantic owner. `SlopadEngine`, `SlopadAppKitUI`, and `SlopadAppKitTextKit` remain
  public advanced/compatibility products.
- `SlopadAppKitTextKit`: AppKit/TextKit2-based block text layout/rendering backend. It does not
  own native view/input host types or canonical editor state.
- `SlopadAppKitUI`: reusable macOS AppKit adapter. It provides AppKit key/pointer/IME
  callbacks, scroll/focus sync, TextKit2 fragment-based text drawing, and the
  `AppKitBlockChromeRenderer` interface, but it does not own engine semantics or canonical
  state. The chrome hook is clipped to its block frame and may draw backgrounds, borders,
  gutters, and markers; text/text-selection/caret drawing remains adapter-owned and
  follows the isolated chrome pass. Replacing the complete native text pipeline requires
  a separate platform adapter with a coherent backend, not a high-level paint hook.
- `SlopadDebugApp`: macOS reference/debug host. Debug-only state such as the debug HUD,
  scenario driver, screenshot capture, and state assertions stays out of the reusable UI
  package.
- `SlopadUIBenchmarkApp`: AppKit UI benchmark harness. Frame loops, CSV output, and forced
  display flushes stay out of the reusable UI package.

`DataStructure` is not a product layer. `PrefixSumRedBlackTree` remains a pure foundational
data structure, while the y/height domain belongs to `BlockHeightIndexStorage`.

`EditorModel` does not call or own `BlockLayout`. `EditorModel` state/change facts are
used by `Session` when it builds `BlockLayout` requests.

## Terminology and Decision Criteria

- `SlopadCoreModel` contains only the public vocabulary needed by host contracts, backend
  seams, and package canonical values. It is not a fallback bucket for projections or
  helpers that became inconvenient during deletion experiments.
- `Document`/`Block` are storable canonical block tree values. The host-facing public
  model is limited to values needed to read the Session contract or backend seam, such as
  `EditorBlockInput`, `EditorInputEvent`, `EditorSelection`, and geometry/layout seam
  values.
- A range inside one block is `Text Selection`; selection of one or more visible blocks is
  `Block Selection`; no selection is `Inactive Selection`. Current multi-block work is
  modeled as block selection, not cross-block text ranges. The assistant context projection
  still handles a public cross-block `TextSelection` value by producing canonical fragments;
  that projection does not add cross-block native editing semantics.
- IME/marked text is not canonical document content. It is a live composition overlay in
  Session runtime state. Ordinary editing exits such as focusing another block, entering
  block selection, or clicking empty space commit composition first. It is discarded only
  when native input sends an explicit cancel.
- `EditorDocumentSnapshot` is the complete canonical host projection in depth-first
  preorder. Selection, layout, scrolling, and live composition do not advance its
  Session-local revision; explicit and implicit composition commits do.
- `EditorDocumentContextSnapshot` is a short-lived review/CAS projection that additionally
  carries exact selection and structured selected content. Neither viewport render state
  nor a persistence revision alone can authorize an `EditorDocumentPatch`.
- A public document patch is a complete canonical DFS post-image, not a command replay.
  Invalid structure, noncanonical mutable `BlockContent`, or invalid selection returns a
  typed error without mutation; an exact no-op creates no revision, history entry, update
  callback, or render work. Validation of unbounded public hierarchy traversal must be
  iterative rather than recursive.
- Context and selected-content structs are output-only Session projections: keep their
  initializers non-public and do not add unchecked `Decodable` conformance. The public
  host-constructed input is `EditorDocumentPatch`.
- `BlockLayout` owns visible order, y/height, hit/reveal geometry, marker projection, and
  layout invalidation. `EditorSession` assembles UI render descriptors and host-facing
  snapshots.
- `TextLayout` does not mean height measurement only. It includes line fragments,
  caret/selection rects, and text hit-testing, so keep the `textLayouter` name and do not
  shrink it to `textMeasurer`.
- A text backend is a coherent geometry contract, not an interchangeable paint callback.
  `EditorSession` supplies live composition to `BlockLayout`'s effective content
  projection; measurement, line fragments, hit testing, caret/selection geometry, and
  drawing must then consume the same effective request. `AppKitBlockChromeRenderer` is
  decoration only; complete native text pipeline replacement requires a separate adapter
  and coherent backend.
- `AppKitEditorViewController` owns one coherent `AppKitTextSystem`. One
  `AppKitEditorStyle` value configures TextKit2 geometry, drawing, IME decoration, and the
  style passed to chrome. Runtime replacement must build and publish that system as one
  atomic configuration unit.
- The ordinary AppKit controller accepts context-free `AppKitEditorAction` values through
  `perform(_:)` and resolves its own viewport. `commitActiveComposition()` is the explicit
  host lifecycle flush. Raw `EditorInputEvent` and the `currentViewport` controller method
  are not public controller surface; `EditorInputEvent` and `EditorViewport` remain
  available at the public `EditorSession` boundary for a complete custom adapter.
- An owner is the layer with final authority over the invariant and mutation rule for a
  meaning. A projection is a derived read/display/calculation result from canonical state
  and does not replace canonical state.
- Add a new type only when it carries a real invariant, reuse point, test surface, or
  cross-layer vocabulary. If deleting it pushes complexity into `SlopadCoreModel`,
  `Session`, test support, or multiple call sites, the deletion did not succeed; the
  interface was wrong.

## Work Loops

- Name the repeated task or risk type first, for example structure change, bug fix,
  performance change, or AppKit adapter surface cleanup.
- Before editing, write at least three completion criteria. They should say which
  observable behavior, owner/interface boundary, test, build, or benchmark will prove
  completion.
- Structure-change loop:
  `owner decision -> type inventory -> deletion/merge/access-shrink experiment ->
  deletion test -> place surviving types by owner/read intent -> verification -> durable
  doc update`.
- Bug-fix loop:
  `symptom -> canonical owner -> why tests missed it -> focused test -> fix -> full
  verification`.
- Performance-change loop:
  `hot-path hypothesis -> 100/1000/10000 benchmark -> counter check -> CSV/doc update ->
  regression risk record`.
- A one-off bug should become a test. A twice-repeated mistake becomes a candidate rule in
  this file. Only structural failure patterns should be added to `docs/LESSONS_LEARNED.md`.
- If the same issue still fails after three fix attempts, stop editing and report the
  candidate causes, failed attempts, remaining uncertainty, and next check.

## UI/UX Feature Workflow

- UI/UX work must verify both visible AppKit behavior and the owning engine behavior; a
  surface change alone is not completion.
- Use `SlopadDebugApp` and the helpers in `scripts/` for real input, focus, selection,
  IME/composition, scrolling, reveal, hit-test, screenshot, and state-regression checks.
- Use `SlopadUIBenchmarkApp` when changes may affect frame time, layout work, redraw,
  text layout cache behavior, drag/reorder, or large-document interaction.
- Separate ownership before fixing UI bugs: AppKit callback/drawing glue belongs to
  `SlopadAppKitUI`; semantic editing, selection, composition, hit-test, reveal, and layout
  orchestration belong behind `EditorSession`.
- Treat public AppKit host actions as synchronized adapter boundaries. `resetDocument`
  `scrollDocument`, `perform(_:)`, and `commitActiveComposition()` must return with the
  relevant Session snapshot, canvas, viewport, native input, focus, and observer state
  consistent. Programmatic scrolling and composition flushes must preserve the specified
  viewport and responder ownership. Package-only no-render hooks are reserved for
  development targets that explicitly perform the later render/sync step.
- Treat `documentContextSnapshot()` and `applyDocumentPatch(_:)` as synchronized sibling
  boundaries rather than `AppKitEditorAction` cases. AppKit rejects native marked text and
  forwards; Session owns composition/source CAS and projection; EditorModel owns atomic
  validation and history.

## Working Principles

- Run `git status --short` before making changes so user-owned uncommitted work is
  visible.
- Before structure/engine/UI package changes, read `README.md`, `docs/ARCHITECTURE.md`,
  relevant ADRs, `docs/ROADMAP.md`, and this file's terminology/decision criteria, then
  summarize the responsibility boundary.
- Judge from repository files and current source, not memory or prior conversation.
- Decide which layer owns the change before editing.
- Reflect layer-boundary changes only in durable sources: README,
  `docs/ARCHITECTURE.md`, AGENTS, ADR, or ROADMAP.
- Access control means `public` for host surface, `package` for real cross-target owner
  interfaces, and omitted access for target-internal defaults. Do not open a whole owner
  helper through `package extension`.
- After changing the AppKit public/package boundary, build
  `Fixtures/DownstreamAppKitHost` without weakening it through `@testable` or package
  access.
- Prefer existing local patterns and helper APIs.
- Keep source/test filenames responsibility-revealing.
- Do not revert user changes.
- Prefer `rg` or `rg --files` for file search.
- Use `apply_patch` for manual file edits.

## Testing Principles

- Tests should reflect source layers and responsibilities.
- Test description metadata should be written in Korean.
- Test bodies should use `// Given`, `// When`, and `// Then`.
- The behavior exercised in `When` should belong to the layer that test file is
  responsible for.
- Behavior owned by another layer should be used as `Given` setup data or split into a
  separate test.
- Prefer basic unit behavior tests before fuzz or broad smoke tests.
- Keep test method names short; write detailed descriptions in Korean in `@Test("테스트 내용...")`
  metadata.

## Verification

Default verification after code changes:

```sh
swift test --quiet
swift build --product SlopadAppKit --quiet
swift build --product SlopadAppKitTextKit --quiet
swift build --product SlopadAppKitUI --quiet
swift build --product SlopadDebugApp --quiet
swift build --product SlopadUIBenchmarkApp --quiet
swift build --package-path Fixtures/DownstreamAppKitHost --product DownstreamAppKitHost --quiet
git diff --check
```

If package or target graph changes, also run `swift package dump-package`.
