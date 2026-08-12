# Architecture

This document is the text reference for SlopadEditor's current ownership and runtime contracts.
[`Package.swift`](../Package.swift) is the compiler-enforced dependency graph, current
source and tests define what the code does, and [ADRs](../ADR/README.md) explain durable
choices. The [interactive architecture map](slopad-architecture-map.html) is the visual
companion to this document; it is a projection, not a separate authority.

The implemented cross-block selection contract lives in
[Selection Interaction Policy](SELECTION_INTERACTION_POLICY.md) and
[ADR 0014](../ADR/0014-latch-selection-mode-and-support-cross-block-text.md). Its
[interactive transition map](selection-interaction-map.html) is a visual projection of
that policy. Canonical two-endpoint selection belongs to `EditorModel`; Session resolves
command spans and visible presentation; AppKit owns physical hit classification, native
callbacks, drawing, pasteboard negotiation, and autoscroll.

## System Shape

SlopadEditor is a headless native block editor. Its canonical document is a tree of blocks;
Markdown and HTML are formats at the edge, not the editor model.

The production targets form these direct dependency layers:

| Layer | Target | Direct role |
| --- | --- | --- |
| Host facade | `SlopadEditorSwiftUI` | SwiftUI lifecycle over the curated AppKit facade |
| Host facade | `SlopadEditorAppKit` | One-product/one-import ordinary macOS surface |
| Platform adapter | `SlopadEditorAppKitUI` | AppKit callbacks, native input, drawing, focus, scroll, surface sync |
| Text backend | `SlopadAppKitTextKit` | TextKit2 implementation of the text-layout capability seam |
| Orchestration | `SlopadEngine` | Public `EditorSession` and editor semantics across owners |
| Canonical owner | `SlopadEditorModel` | Document, selection, commands, transactions, history |
| Derived owner | `SlopadBlockLayout` | Visibility, block geometry, hit/reveal facts, caches, height index |
| Format syntax | `SlopadEditorMarkdownInputRules` | Internal immutable bounded typed-input patterns |
| Format codec | `SlopadEditorMarkdown` | Opt-in stateless whole-document decode and encode |
| Format codec | `SlopadEditorArchive` | Opt-in stateless versioned native archive encode and decode |
| Contracts | `SlopadCoreModel` | Public vocabulary and genuine package cross-target contracts |
| Storage | `SlopadEditorDataStructure` | Editor-independent data structures |

`SlopadEditorArchive` is an opt-in synchronous pure codec whose target depends only on
`SlopadCoreModel`. Its public facade uses Swift 6 `public import` for declaration legality
and exposes only five type-identical archive aliases; it does not make `SlopadCoreModel` a
product or broadly re-export its vocabulary. See
[ADR 0015](../ADR/0015-version-native-archive-and-keep-storage-host-owned.md).

The dependency graph enforces four important absences:

- `SlopadEditorModel` and `SlopadBlockLayout` do not import each other;
  `EditorSession` coordinates them.
- `SlopadAppKitTextKit` does not import the engine. Runtime calls arrive through
  `BlockTextLayoutProtocol` capabilities defined in `SlopadCoreModel`.
- `SlopadEditorMarkdown` does not import the engine. A caller explicitly decides when decoded
  block inputs enter a document transaction.
- `SlopadEditorArchive` likewise does not import the engine or a storage provider. It
  transforms canonical block inputs to/from `Data`; the host owns persistence lifecycle.
- `SlopadEditorAppKit` and `SlopadEditorSwiftUI` add no second controller, Session, document, or cache.

Debug apps, benchmarks, tests, and downstream fixtures are outer-edge consumers. They
verify production owners but do not define editor behavior.

## Ownership and State Lifetimes

One meaning has one authority. Similar-looking values with different lifetimes are not
interchangeable.

| Lifetime | Owner | Examples | Rule |
| --- | --- | --- | --- |
| Canonical document | `SlopadEditorModel` stores types defined in `SlopadCoreModel` | block tree/order, `BlockID`, kind, text, inline marks | Changes only through validated model transactions |
| Canonical editing state | `SlopadEditorModel` | caret/text/block selection, stored marks, history | Platform callbacks request transitions; they do not mutate it directly |
| Session runtime | `EditorSession` | live composition, composition selection, slash query/source revision, drag/navigation context | Cleared or invalidated when its exact source state no longer matches |
| Platform runtime | `SlopadEditorAppKitUI` | responder, native marked range, scroll position, overlay widgets | Must converge on Session facts without becoming semantics |
| Derived layout | `SlopadBlockLayout` and text backend | visible order, y/height index, prepared text layout, hit/caret/selection geometry | Rebuildable from canonical plus runtime inputs; never persisted as document state |
| Render projection | `EditorSessionSnapshot` | visible blocks, active text input, overlays, total height | Viewport-scoped and disposable |
| Persistence projection | `EditorDocumentSnapshot` | complete canonical DFS block inputs and Session epoch/revision | Full-tree read; excludes selection, layout, viewport, scroll, and composition |
| Review context | `EditorDocumentContextSnapshot` | full document, exact selection, selected content, opaque source | Short-lived CAS authority used only by `applyDocumentPatch(_:)` |

Canonical value definitions living in `SlopadCoreModel` do not make that target the
mutation owner. Likewise, a complete TextKit prepared graph is a derived cache entry, not
canonical editor state.

## Runtime Paths

The paths below identify the real producer-consumer direction. Each path must preserve the
owner boundary even when optimized.

The IME row describes the callback contract implemented after an event reaches
`NSTextInputClient`. Direct `setMarkedText` tests exercise that consumer, but installed
input-method delivery requires separate product-path evidence. A 2026-08-10 diagnostic
session observed one Apple Korean 2-set marked update reach the consumer, but did not verify
the complete commit/cancel lifecycle or candidate-window behavior. The current consumer
keeps a Session overlay until commit; reproducible installed delivery and the live
replacement policy in ADR 0014 remain unfinished product work.

| Interaction | Producer-to-consumer path | Invariant |
| --- | --- | --- |
| Typing/IME | AppKit callback → `SlopadEditorAppKitUI` → `EditorSession.handleInput` → model transaction → layout invalidation → snapshot → synchronized native surface | Composition is a Session overlay until commit; canonical selection stays in canonical coordinates |
| Text pointer selection | AppKit point → Session pointer event → `SlopadBlockLayout` block hit → text backend grapheme hit → Session selection transition → snapshot | Backend returns facts; Session owns selection meaning |
| Block selection/drag | AppKit gutter/body routing → Session runtime preview → layout drop/reveal geometry → model move transaction on successful drop | Preview is runtime state; only the final valid drop mutates the tree |
| Slash command | Model typed-`/` rule → Session query/source runtime → snapshot anchor/catalog → AppKit overlay → Session CAS apply → one model transaction | Query/menu state is not canonical; `/query` deletion and kind change form one undo step |
| Rendering/scroll | AppKit viewport → `EditorSession.render` → block visibility/layout → coherent text backend facts → render snapshot → AppKit surface sync | Only visible projection is rendered; it is not a persistence source |
| Persistence | model semantic change → Session committed revision → host callback → on-demand `documentSnapshot` → host debounce → archive encode → host storage | Snapshot blocks are the source; epoch/revision only reject stale in-process work and are never stored |
| Reviewed replacement | context snapshot → external review → complete patch → Session epoch/revision/selection CAS → model validation/replacement → layout/runtime invalidation | A changed post-image is one transaction; stale, invalid, or composing sources fail without partial mutation |
| Markdown import/export | caller → `SlopadEditorMarkdown` → fresh `[EditorBlockInput]` or deterministic text → optional Session patch | Codec AST never crosses its target and no conversion is implicit |
| Native archive reload | host bytes → `SlopadEditorArchive` raw wire validation → canonical input validation → `[EditorBlockInput]` → explicit host Session lifecycle | Identity/order/content survive; malformed or unsupported archives return no partial blocks |

### Synchronized AppKit actions

An ordinary host uses context-free `AppKitEditorAction` values through `perform(_:)`.
`AppKitEditorViewController` supplies the current viewport and synchronizes the Session
snapshot, canvas, native text/selection, responder, scroll, and observers before returning.
If live composition exists, it is committed and synchronized before the requested action;
the host may therefore observe one update for the composition commit and one for the
action.

`commitActiveComposition()` is the explicit persistence, document-switch, and close
lifecycle flush. `resetDocument`, `scrollDocument`, `updateEditorStyle`, focus operations,
document patching, and snapshot reads are also synchronized controller boundaries. Raw
`EditorInputEvent`, controller viewport ownership, and no-render batching helpers are not
ordinary-host API.

### Scrolling and sizing

The default editor owns its internal `NSScrollView`. Embedding it inside another scrolling
container is unsupported because it creates two viewport owners. A host that wants an
inline editor sizes the container from `contentHeight`/`onContentHeightChange`; when the
container is smaller than the content, the editor still scrolls internally.

## TextKit Boundary

`BlockTextLayoutProtocol` is a coherent capability bundle, not a height callback or paint
hook.

| Capability | Backend answers | Semantic owner after the answer |
| --- | --- | --- |
| `BlockMeasuring` | text height and measurement result for an effective request | `SlopadBlockLayout` caches and places blocks |
| `TextGeometryResolving` | fragments, hit positions, caret and selection rects | Session assembles render/input facts |
| `TextNavigationResolving` | physical/linguistic movement facts and transient bidi context | Session changes canonical selection and crosses block boundaries |
| `TextDeletionResolving` | Unicode-aware deletion range | Session/model applies the edit and history |

One `AppKitTextSystem` and one `AppKitEditorStyle` keep measurement, drawing, hit testing,
caret/selection geometry, marked text, and navigation based on the same effective content.
`TextKitPreparedLayoutStore` reuses complete coherent TextKit graphs with deterministic
bounded eviction. Cache identity follows measurement request values and style, not a
loosely related revision convention.

For custom adapters importing `SlopadAppKitTextKit` directly, `TextKitTextSystem` is the
supported construction boundary. Its public `layouter` and `renderer` share one internal
`TextKitLayoutContext`; their standalone initializers remain internal. This preserves the
coherent-backend invariant outside the default `AppKitTextSystem` path without exposing
the prepared TextKit object graph.

`AppKitBlockChromeRenderer` is decoration-only: backgrounds, borders, gutters, and markers.
The adapter clips and isolates chrome, then always draws TextKit fragments plus selection,
caret, and marked-text feedback. A host needing different text rendering must replace the
complete adapter/backend pair so geometry and drawing stay coherent.

## Host Surfaces

| Consumer | Recommended surface | Consumer owns | Consumer must not reach into |
| --- | --- | --- | --- |
| Ordinary macOS app | `SlopadEditorAppKit` | document storage policy, app chrome, lifecycle | raw TextKit graph, model/layout internals |
| SwiftUI app | `SlopadEditorSwiftUI` | mount/unmount, document identity, bindings, persistence timing | controller bypass or a second runtime |
| Complete custom platform adapter | `SlopadEngine` plus its own backend | native callback translation, drawing, focus, scroll coherence | direct model/layout coupling |
| Markdown caller | `SlopadEditorMarkdown` and optionally `SlopadEngine` | explicit import/export timing and failure UX | parser AST retention or partial success |
| Native archive codec caller | `SlopadEditorArchive` | construct/encode/decode the curated archive aliases | raw Engine/CoreModel imports, Session state, storage providers, or a second canonical document owner |
| Native archive lifecycle host | exactly one public UI facade plus `SlopadEditorArchive` | file/DB/cloud lifecycle, debounce, atomic write, conflict/retry/error UX | raw Engine/CoreModel imports, package-only state, or codec-owned lifecycle policy |
| Debug/benchmark/fixture | development targets | scenarios, measurements, public compile proof | production ownership |

The ordinary AppKit host surface is admitted by intent:

| Host intent | Public contract |
| --- | --- |
| Create or replace a document | controller initialization, `resetDocument` |
| Perform an edit | `perform(_:)` with `AppKitEditorAction` |
| Move focus/selection | synchronized focus APIs and actions |
| Flush IME before save/switch/close | `commitActiveComposition()` |
| Observe and persist | `onUpdate`, `documentSnapshot` |
| Review and atomically replace | `documentContextSnapshot()`, `applyDocumentPatch(_:)` |
| Change default presentation | `updateEditorStyle(_:)` |
| Draw block decoration | `AppKitBlockChromeRenderer` |

`SlopadEditorSwiftUI` packages the mount → edit → observe → flush → replace → unmount lifecycle.
It guards document identity, filters committed changes, bridges focus, and flushes
composition before persistence without re-exporting the controller.

The built-in floating formatting toolbar and todo checkbox remain AppKit adapter chrome.
They consume package-only Session command/selection projections and send typed actions back
through Session/model transactions. Existing programmatic host actions use the same
Session resolver, but command availability, mixed state, selection presentation, checkbox
hit geometry, and toolbar placement are not public host state. Epic #67 has no concrete
host-owned toolbar consumer that passes ADR 0012's three-part exposure test, so adding such
state is explicitly outside its scope; a future consumer requires its own boundary review.
The continuous host gate type-checks each excluded symbol from a separate external consumer
source after positive facade lookup succeeds, so it measures compiler visibility rather
than declaration spelling. What each probe pins depends on the symbol's access level, and
the two claims are not interchangeable.

Package and internal symbols — the command state, selection projections, floating toolbar,
todo checkbox, and block layout — are probed through their own declaring module. They stay
unreachable however an external consumer imports, which is the claim that matters for
symbols whose exposure would widen the host contract.

Symbols that are public in another module are probed only through the facade, and that
pins only that the facade does not re-export them. SwiftPM gives a downstream target a
single import path covering every built module, so a host that declared only the
`SlopadEditorAppKit` product can still write `import SlopadAppKitTextKit` and reach
`TextKitTextSystem`; `--explicit-target-dependency-import-check error` does not prevent
this across packages. Such a host has imported a module it never declared, which review
catches, but the compiler does not.

## Markdown Boundaries

Markdown has two deliberately separate entry points:

- `SlopadEditorMarkdownInputRules` contains parser-free bounded prefix/inline patterns linked
  into ordinary editing. `SlopadEditorModel` owns trigger classification, candidate
  evaluation, canonical mutation, and undo.
- `SlopadEditorMarkdown` is an opt-in whole-document codec. It accepts/returns public
  `[EditorBlockInput]` values and depends on `swift-markdown`; it owns no editor runtime.

Decode and encode are stateless and fail closed with nonempty typed diagnostics. Decode
creates fresh IDs. The supported round-trip contract preserves canonical tree/content
semantics rather than source spelling or identity. Parser AST types remain internal:
only `Sources/SlopadEditorMarkdown` may use `internal import Markdown`.

The codec is not a plugin registry, persistence choice, or paste fallback. Callers decide
when to import/export and how to present unsupported input. See
[ADR 0013](../ADR/0013-markdown-format-boundary.md).

## Native Archive Boundary

`SlopadEditorArchive` v1 is a separate opt-in `SlopadCoreModel`-only codec over UTF-8 JSON
`Data`. Its envelope contains `formatVersion` and the complete canonical preorder blocks
only. It preserves IDs, parent/root/sibling order, kinds, text, and inline marks; it excludes
selection, history, operation journal, external reference payloads, epoch/revision,
composition, layout, viewport, and TextKit state.

The target internally depends on `SlopadCoreModel`, and files declaring public signatures
use Swift 6 `public import SlopadCoreModel`. The archive module itself declares only
typealiases for `BlockID`, `BlockKind`, `BlockContent`, `TextRange`, and
`EditorBlockInput`; nested kind/mark vocabulary remains reachable through those aliases.
There is no `SlopadCoreModel` product, Engine dependency, copied wrapper model, or blanket
`@_exported import`. All archive signatures and associated error values use those exact
aliases, so blocks obtained through any UI or Engine facade are type-identical and need no
conversion.

Decode is fail-closed. Archive-owned raw wire DTOs are checked before constructing
normalizing `BlockContent` values. A package-only strict CoreModel content constructor
rejects any mark list that would clamp/drop/merge/reorder; then a selection-independent
CoreModel validator checks empty/duplicate/parent/cycle/content/preorder invariants.
Malformed data, unsupported future/past versions, and canonical invariant failures return
no blocks. Encoding validates the same invariant and returns no bytes on failure. The
semantic result is deterministic; JSON byte identity is not promised.

The host observes a committed revision, coalesces notifications, reads the latest snapshot
on the Session executor, and synchronously registers the captured storage token before it
posts immutable blocks to background encoding. Its persistence owner protects final token
admission, atomic replacement, and persisted-token publication as one throwing commit.
Registration shares that authority, invalidates an older persisted token, and may briefly
block behind the filesystem rename; byte encoding and temporary-file preparation remain
outside the gate. Result delivery rechecks the current token, document ID, and generation on
the Session-owning executor. Epoch/revision remain
in-process freshness facts and are neither archive fields nor storage revisions. A separately stored reference
may reattach by stable `BlockID`, but selection and undo/history do not restore. See
[ADR 0015](../ADR/0015-version-native-archive-and-keep-storage-host-owned.md).

The V1 parser and encoder share bounded byte, value, collection-member, decoded-string,
and depth admission budgets. Encoding performs its allocation-bounded traversal before Core
canonical validation. These are wire-safety rules, not performance thresholds; excess input
fails without a partial document or oversized output.

`Fixtures/DownstreamArchiveHost` proves the public boundary with two external
targets/sources. The codec-surface
probe depends on/imports only Foundation and `SlopadEditorArchive`, constructs the aliased graph,
and round-trips it. The lifecycle probe may additionally import exactly one public UI
facade and passes its `snapshot.blocks` directly to the codec; it never imports raw Engine,
CoreModel, or package-only types. A single fixture package may contain both only as separate
targets/sources with distinct dependency and import audits.

## Access and Consumer Rules

- `public` means a supported host contract.
- `package` means a genuine cross-target owner contract.
- `internal` and `private` hold owner-local policy, cache state, and helpers.
- Downstream fixtures verify public usage without `@testable`, package access, or direct
  dependencies that bypass the intended facade.
- Tests target the layer that owns the behavior; test-folder symmetry is not an
  architecture goal.

## Change Decision Checklist

Before changing a boundary, answer these in order:

1. What meaning is changing, and which layer owns it today?
2. Is the proposed value canonical, runtime, derived, or a host projection?
3. What is the real producer-consumer path in current source?
4. Can the existing owner express the change without a new cross-target type?
5. Does a new host API pass the [ADR 0012](../ADR/0012-host-embedding-contract.md)
   three-part test: impossible to derive correctly outside, needed by a real consumer,
   and publishable without exposing internals?
6. Does the change preserve coherent native text measurement, geometry, navigation, and
   drawing?
7. Which owner tests, downstream fixtures, debug scenarios, or benchmarks prove it?

The most relevant durable decisions are:

- [ADR 0001](../ADR/0001-headless-session-facade.md) — headless Session facade
- [ADR 0002](../ADR/0002-swiftpm-target-graph.md) — compiler dependency graph
- [ADR 0007](../ADR/0007-appkit-ui-adapter-package.md) — reusable AppKit adapter
- [ADR 0008](../ADR/0008-keep-editor-session-executor-confined.md) — Session isolation
- [ADR 0009](../ADR/0009-publish-committed-document-snapshots.md) — persistence projection
- [ADR 0010](../ADR/0010-appkit-platform-facade.md) — ordinary AppKit facade
- [ADR 0011](../ADR/0011-reviewable-atomic-document-transactions.md) — reviewed patches
- [ADR 0012](../ADR/0012-host-embedding-contract.md) — host surface admission
- [ADR 0013](../ADR/0013-markdown-format-boundary.md) — Markdown isolation
- [ADR 0014](../ADR/0014-latch-selection-mode-and-support-cross-block-text.md) — committed
  composition publication
- [ADR 0015](../ADR/0015-version-native-archive-and-keep-storage-host-owned.md) — native
  archive and host-owned storage lifecycle
