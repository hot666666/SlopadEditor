# ROADMAP

This document keeps only the current development direction for the Slopad project. See
[Architecture](ARCHITECTURE.md) for the current target graph, ownership model, and
platform extension philosophy.

This file, together with `ADR/` and the active tracking issue, is the single source of
truth for **what the code should become**. Current source and tests remain the authority
for **what the code does today**. When the two disagree about intent, correct this
document first, then change code.

`Slopad_Semantic_Editor_Architecture_Handoff.md` is a background record of how the current
direction was reached. It is not a work order, and its Phase list is superseded by the
active epic below.

## Active Epic

**[Epic #23 — Markdown-semantic 편집 계층 정립](https://github.com/hot666666/Slopad/issues/23)**

[Current integration status](epic-23-status.html)

Two tracks run in parallel; they do not share files.

| Track | Issues | Focus |
| --- | --- | --- |
| A — semantics | [#24](https://github.com/hot666666/Slopad/issues/24) [#25](https://github.com/hot666666/Slopad/issues/25) [#26](https://github.com/hot666666/Slopad/issues/26) [#27](https://github.com/hot666666/Slopad/issues/27) [#28](https://github.com/hot666666/Slopad/issues/28) [#29](https://github.com/hot666666/Slopad/issues/29) [#30](https://github.com/hot666666/Slopad/issues/30) [#31](https://github.com/hot666666/Slopad/issues/31) [#32](https://github.com/hot666666/Slopad/issues/32) [#33](https://github.com/hot666666/Slopad/issues/33) | inline mark reachability, editing state, command vocabulary, input rules, Markdown decode/encode |
| B — layout | [#34](https://github.com/hot666666/Slopad/issues/34) [#35](https://github.com/hot666666/Slopad/issues/35) [#36](https://github.com/hot666666/Slopad/issues/36) [#37](https://github.com/hot666666/Slopad/issues/37) | text capability split, caret geometry path, cache key alignment, prepared layout store |

The semantic foundation through [#30](https://github.com/hot666666/Slopad/issues/30), plus
layout issues
[#34](https://github.com/hot666666/Slopad/issues/34) through
[#36](https://github.com/hot666666/Slopad/issues/36), are implemented. The decoder now
unblocks inline rules in [#31](https://github.com/hot666666/Slopad/issues/31) and encoding
in [#32](https://github.com/hot666666/Slopad/issues/32). Track B's prepared-layout store
remains open in [#37](https://github.com/hot666666/Slopad/issues/37).

### Decisions fixed for this epic

These are settled. Sub-issues implement them rather than re-opening them.

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | caret geometry is published through the Session snapshot; AppKit UI does not call the text backend directly | UI then needs only the rendering contract. focus, damage, and content height already travel that path |
| D2 | no cross-block text ranges; multi-block work stays block selection | allowing them pulls in split/join position mapping, which requires the global integer coordinate space that is an explicit non-goal |
| D3 | measurement keys align on `BlockMeasureRequest` value equality; no new revision-based key | `PreparedLayoutKey = (BlockMeasureRequest, TextKitEditorStyle)` already makes "same key implies same layout" true by construction. A revision key would weaken that to a convention |
| D4 | `BlockKind` stays a closed enum; no open `typeID` with dynamic payload | the Markdown block vocabulary is closed by its specification. Opening it loses exhaustive `switch` checking and requires unknown-type preservation machinery with no consumer |
| D5 | structure and content maps are not split | Swift's `[BlockID: Block]` is already copy-on-write, so most of the expected benefit is automatic. Splitting adds a key-set agreement invariant. Revisit when lazy content loading is real |
| D6 | no format plugin protocol or registry | there is one format implementation. The point of a separate target is isolating the `swift-markdown` AST, not extensibility |
| D7 | the inline mark vocabulary is a closed set owned by the core; neither format nor backend may extend it | `TextKitAttributedStringBuilder` already only interprets marks. What a format cannot express becomes an encoder diagnostic, not a new mark |

### Out of scope for this epic

- `DocumentStep` / `PositionMap` — blocked by D2; snapshot history stays.
- `DocumentSchema` / `BlockSpec` / `MarkSpec` — `Document+Invariants.swift` already
  enforces the listed checks, and extension blocks have no first consumer.
- Persistence source-of-truth choice — the round-trip criterion is now fixed by
  [ADR 0013](../ADR/0013-markdown-format-boundary.md). Markdown does not preserve
  `BlockID`s or source spelling; a later persistence ADR must decide whether to accept that
  discontinuity or choose a native archive or hybrid/sidecar.
- HTML artifact and image blocks — consuming-product requirements that cannot yet be
  expressed as engine-verifiable completion criteria. GFM tables are not a permanent
  product non-goal: [#50](https://github.com/hot666666/Slopad/issues/50) first expands the
  Core table vocabulary, after which the Markdown adapter adds lossless table support.
  This epic and #30 deliberately return the typed `.table` diagnostic until that Core
  contract exists.

## Achieved Baseline

- The headless `EditorSession` facade is the host-facing surface.
- Committed content and structure changes publish a Session-local monotonic revision. A
  host can read a viewport-independent full canonical `EditorDocumentSnapshot` on demand;
  selection, scrolling, layout, and live IME composition do not publish persistence
  changes.
- Review-before-apply integrations can capture an `EditorDocumentContextSnapshot` and
  submit an `EditorDocumentPatch` full post-image. Its opaque source exact-CASes Session
  epoch, committed revision, and selection; composition and stale sources are typed
  rejections. Valid changed post-images commit as one model transaction and one update,
  while exact no-ops create no revision or history. Mutable content canonicality is
  checked with typed rollback, and deep hierarchy/cycle validation is iterative.
- The SwiftPM target split is complete. `SlopadEngine` composes `SlopadEditorModel` and
  `SlopadBlockLayout`; those two targets do not import each other.
- `SlopadCoreModel` contains only public vocabulary, backend seams, and package canonical
  document values.
- The opt-in `SlopadMarkdown` target pins `swift-markdown` 0.8.0 exactly and exposes one
  stateless typed-throws decode into fresh depth-first `[EditorBlockInput]` values. Its AST
  stays behind `internal import Markdown`; unsupported syntax produces nonempty typed
  source diagnostics and no partial blocks. A separate downstream fixture applies that
  output unchanged through an inactive-selection `EditorDocumentPatch` and `EditorSession`.
- `SlopadAppKit` is the recommended ordinary macOS host product and import. It curates
  the default AppKit controller, action, style, chrome, document, selection, update, and
  snapshot vocabulary without becoming a runtime owner.
- `SlopadAppKitTextKit` provides the AppKit/TextKit2-based measurement, line fragment,
  caret/selection rect, hit-test, Unicode navigation, and drawing backend.
- The default `BlockHeightIndexStorage` implementation is RBTree-backed. Array storage is
  not the default for structural-mutation-heavy paths.
- The viewport-driven lazy initial layout baseline is in place. Large documents exact-
  measure blocks around the viewport and start the rest from cached/estimated heights.
- The `SlopadAppKitUI` target provides the reusable AppKit view/controller/input/render
  adapter assembled by `SlopadAppKit`. Its product remains available for advanced and
  compatibility integrations. The adapter also handles edge autoscroll near the
  top/bottom of the viewport during block selection rectangles, gutter block selection,
  and block reorder.
- AppKit block appearance customization is a chrome-only public contract. Host renderers
  can draw backgrounds, borders, gutters, and markers, while the adapter always owns
  TextKit2 fragment-based text drawing with effective live composition, followed by
  text-selection and caret feedback after clipped and isolated host chrome passes.
- Public AppKit `resetDocument` and `scrollDocument` actions are synchronized boundaries.
  Reset updates the replacement document and native surface before returning; scroll
  updates viewport, visible snapshot, canvas, and observers without discarding live
  marked text or stealing focus. Unsynchronized batching helpers remain package-only.
- Programmatic default-adapter editing uses context-free `AppKitEditorAction` values via
  `perform(_:)`; the controller supplies its current viewport when a command needs it.
  `commitActiveComposition()` provides the explicit persistence/document-lifecycle flush.
  Raw `EditorInputEvent` and `currentViewport` are not public controller APIs.
- `AppKitEditorViewController` owns one coherent `AppKitTextSystem`. One
  `AppKitEditorStyle` value configures TextKit2 geometry, drawing, IME decoration, and
  block chrome style together, including during runtime replacement.
- `Fixtures/DownstreamAppKitHost` compile-checks the intended downstream API with one
  `SlopadAppKit` product dependency and one regular import, and executes the public
  context/patch round trip without underlying-module access.
- `Fixtures/DownstreamSwiftUIHost` does the same for `SlopadSwiftUI`, covering what a
  window-filling fixture cannot see: embedding as one subview, identity-guarded document
  replacement, committed-change filtering, focus binding, and the composition flush before
  a host reads the document to persist it.
- [Architecture](ARCHITECTURE.md) records the compiler dependency graph, runtime owner
  flow, chrome-only AppKit extension boundary, and complete adapter/backend replacement
  path.
- The AppKit path already routes native command selectors, IME/marked text, plain-text
  copy/cut/paste, undo/redo, scroll reveal, text selection, block selection, block
  selection rectangles, and selected-block drag/reorder through `EditorSession`.
- Physical character movement and Unicode word movement/selection/deletion are resolved by
  the active text backend against Session's effective text request; canonical selection,
  block-boundary transitions, commands, and history remain engine-owned.
- Bidirectional physical traversal keeps its layout-derived inline context in Session
  runtime state only and invalidates it whenever the matching selection/request changes.
- Custom adapters driving `EditorSession` directly still construct raw
  `EditorInputEvent` values and pass `EditorViewport` where engine navigation commands
  require it. That advanced Session surface is separate from the ordinary AppKit facade.
- The editing model already supports block split/merge, indent/outdent, block movement,
  block kind changes, todo toggling, snapshot-based undo/redo with a bounded budget, and
  markdown prefix shortcuts for common block kinds.
- The inline content model stores `strong`, `emphasis`, `code`, `strikethrough`, and `link`
  marks; legacy `bold`/`italic` spellings decode to the format-neutral names. Public Session
  commands toggle or clear them for a selection, caret-only styles live in transient
  `EditorState.storedMarks`, and the TextKit backend consumes the resulting inline runs for
  measurement and rendering.
- The AppKit UI benchmark harness covers scroll, native insert, composition, height
  expansion, block selection, block reorder, mixed interaction, subtree delete, and
  subtree reorder plus runtime style replacement and Unicode navigation at
  100/1000/10000 block scales. Unicode navigation also has a 100/1000/10000-grapheme
  active-paragraph sweep.

## Current Product Gaps

These are not a request to rebuild existing behavior. They are the missing contracts
needed before a host app can use the engine as a Notion/Craft-style editor surface.

- Product hosts may eventually need platform behavior beyond the default AppKit policy.
  That is not a reason to expose raw key, IME, reveal, pointer, or paint hooks from
  `SlopadAppKit`: each request must first be classified as a synchronized host action,
  chrome/style customization, engine input contract, or a separate custom adapter need.
- Clipboard support is currently plain text. Structured block copy/paste, rich inline
  paste, and format negotiation with platform pasteboards are not yet modeled.
- Session input now exposes `toggleInlineStyle` and `clearInlineStyles`, including the real
  AppKit `replaceText` path, and caret-only `storedMarks` apply to the next insertion. Default
  product chrome still has no toolbar/menu/slash discovery UI for those commands;
  [#33](https://github.com/hot666666/Slopad/issues/33) owns the slash-command part only.
- Physical character and linguistic word navigation now use the text backend, but native
  soft-line beginning/end commands still resolve to logical block start/end. A complete
  bidi insertion contract must also decide whether a backend secondary insertion location
  needs platform-neutral state beyond the current transient inline navigation context.
- Block kind transforms exist inside `EditorModel`, and markdown prefix shortcuts exercise
  them, but product commands such as slash menu block transform, toolbar transform, and
  todo checkbox toggling still need host-facing input events.
- The document is tree-capable, but collapsed subtree state, visible-order filtering,
  selection behavior, reveal behavior, and copy/paste behavior for collapsed content are
  not implemented.
- Markdown decoding now exists as a format adapter. Product import wiring, Markdown
  encoding, and broad import/export UX remain separate from markdown prefix shortcuts.

## Next Direction

These are long-range capability buckets, not the active issue queue. While epic #23 is open,
its dependency order in [Active Epic](#active-epic) controls execution; #30 now unlocks
#31 and #32 while dependency-ready #33 remains a separate product-UI branch.

- P0 - AppKit integration contract hardening
  - Stabilize the reusable AppKit host surface before adding large product features.
  - Keep public visual customization limited to `AppKitEditorStyle` and
    `AppKitBlockChromeRenderer`; keep controller actions and observers synchronized host
    operations rather than arbitrary policy hooks.
  - Keep `SlopadAppKit` as the ordinary one-product/one-import integration path while the
    underlying Engine, UI adapter, and TextKit2 backend products remain advanced seams.
  - Add new ordinary programmatic operations as context-free `AppKitEditorAction` cases
    or explicit synchronized controller actions; do not return raw viewport ownership to
    the host.
  - Keep native key mapping, IME transport, reveal, pointer routing, fragment drawing,
    focus, scroll, and surface synchronization inside the default adapter. Semantic
    editing behavior stays behind `EditorSession`.
  - When a host needs a different native pipeline or policy model, use a separate platform
    adapter with a coherent backend instead of widening the default high-level paint
    surface.
  - Add a host-facing capability only when it passes all three parts of the ADR 0012
    exposure test; "a host would find this convenient" is not sufficient.
  - Contract regression gate: **both** `Fixtures/DownstreamAppKitHost` and
    `Fixtures/DownstreamSwiftUIHost` continue to build without `@testable`, direct
    underlying-product dependencies, package-only controller state, raw callbacks, or
    development hooks. A fixture that compiles while avoiding the difficult path is not a
    gate, so each exercises the full mount → edit → observe → flush → replace → unmount
    sequence.
  - Completion signal: downstream hosts can use synchronized actions plus chrome/style
    customization without reaching into native adapter internals, `EditorModel`,
    `BlockLayout`, layout cache, or canonical `Document`.

- P1 - Block interaction UX contract
  - Turn the existing block selection, selection rectangle, drag/reorder, Enter, Escape,
    Delete, cut, copy, paste, and select-all behavior into an explicit product contract.
  - Define structured block copy/paste semantics separately from existing plain-text
    clipboard behavior.
  - Preserve the current model that multi-block work is block selection, not cross-block
    text ranges.
  - Completion signal: each user-visible block selection transition has a Session test and
    a real AppKit verification path.

- P2 - Product command surface and slash discovery
  - Inline formatting reachability, caret `storedMarks`, and the command vocabulary split
    are complete in [#25](https://github.com/hot666666/Slopad/issues/25) through
    [#27](https://github.com/hot666666/Slopad/issues/27).
  - [#33](https://github.com/hot666666/Slopad/issues/33) adds the remaining slash-only
    command catalog and AppKit menu for block transforms. Toolbar UI and generalized
    suggestion triggers remain outside that issue.
  - Keep canonical `BlockKind`, `BlockContent.InlineMark`, and `EditorModel` command owners;
    product UI selects commands and routes them through `EditorSession` rather than owning
    mutation semantics.
  - Completion signal: the slash menu applies a block command as one transaction and one undo
    without exposing `EditorModel` or storing suggestion UI state canonically.

- P3 - Structured paste and Markdown import/export
  - The dependency boundary and the round-trip guarantee are settled in
    [ADR 0013](../ADR/0013-markdown-format-boundary.md): `swift-markdown` lives behind
    `SlopadMarkdown` alone, its exact 0.8.0 dependency requires a Swift 6.2-or-later
    resolving toolchain, and round-trip is semantic rather than byte-exact. `BlockID`s do
    not survive it; the later persistence ADR decides whether Markdown-only storage may
    accept that discontinuity or needs a native archive or sidecar.
  - The decoder side is implemented: it preserves supported block trees and inline marks,
    produces fresh IDs, and fails closed with typed UTF-8 source diagnostics. #32 owns the
    matching encoder; product import/paste policy remains caller work.
  - Keep markdown as import/export format and input shortcut syntax, not canonical state.
  - Add structured block paste before broad markdown import/export if product editing
    needs copy/paste workflows first.
  - Preserve inline marks and block tree structure when Markdown can represent them. The
    decoder fails closed with typed diagnostics for unsupported constructs; choosing a
    separate plain-text paste fallback is caller policy, not a lossy decoder behavior.
  - Completion signal: paste/import behavior round-trips through canonical `Document` and
    has focused engine tests plus AppKit pasteboard coverage.

- P4 - Collapsed subtree feature
  - Add collapsed state without making collapsed visibility canonical document content
    unless the owner decision proves it should be stored there.
  - Update visible-order, selection, reveal, hit-test, render, copy/paste, drag/drop, and
    benchmark scenarios for collapsed content.
  - Completion signal: collapsed subtrees change visible layout and interaction behavior
    without corrupting canonical tree structure or block selection semantics.

- P5 - Performance gates for product UX
  - Extend the existing 100/1000/10000 AppKit and session benchmark coverage as new UX
    paths land.
  - Define thresholds for ordinary typing, composition, text selection, block selection,
    structured paste, collapsed subtree reveal, and subtree reorder.
  - Keep ordinary typing bounded around changed blocks and structural editing bounded by
    ordered diff range where possible.
  - Re-check blockID-based measurement invalidation cost in large caches and design a
    secondary cache-key index only if measured data shows it is needed.
  - Explore coalescing or delta strategies to reduce snapshot undo/redo memory cost.

- P6 - Platform expansion
  - Design a UIKit adapter only after the AppKit adapter contract is stable enough to be a
    reusable reference.
  - Preserve the `EditorSession` semantic boundary and `BlockTextLayoutProtocol` seam when
    adding a platform adapter or text backend beyond AppKit/TextKit2.

## Open Risks

- TextKit2 geometry is sensitive to OS/font/layout-manager behavior, so unit tests should
  focus on invariants.
- If the AppKit facade or UI adapter accumulates too many convenience features, platform
  code can start owning engine semantics again. The facade should curate synchronized
  host contracts, and the adapter should stay focused on callback translation, drawing,
  and focus/scroll sync.
- Treating block appearance customization as a partial text renderer would split the
  geometry pipeline and can duplicate or suppress text, selection, caret, or marked-text
  feedback. Complete replacement belongs in a separate adapter/backend pair.
- If public product commands are added by exposing internal `EditorModel` or `BlockLayout`
  types, the host-facing Session boundary will regress.
- Structured paste can easily become a second canonical model. Paste/import should always
  normalize into the tree-capable `Document`/`Block` store.
- Collapsed subtree state needs an owner decision before implementation. Treating it as
  both canonical document content and runtime visibility policy would create conflicting
  sources of truth.
- Full-rebuild layout remains the correctness baseline, but large documents need both
  incremental layout and viewport-driven lazy measurement paths.
- Snapshot undo/redo is simple and correct, but memory cost can become high for large
  documents.
- Markdown prefix shortcuts and the opt-in fail-closed decoder are implemented, but the
  encoder, broad product import/export, and rich paste are still separate features.
