# Architecture

This document is the text reference for Slopad's current ownership and runtime contracts.
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

Slopad is a headless native block editor. Its canonical document is a tree of blocks;
Markdown and HTML are formats at the edge, not the editor model.

The production targets form these direct dependency layers:

| Layer | Target | Direct role |
| --- | --- | --- |
| Host facade | `SlopadSwiftUI` | SwiftUI lifecycle over the curated AppKit facade |
| Host facade | `SlopadAppKit` | One-product/one-import ordinary macOS surface |
| Platform adapter | `SlopadAppKitUI` | AppKit callbacks, native input, drawing, focus, scroll, surface sync |
| Text backend | `SlopadAppKitTextKit` | TextKit2 implementation of the text-layout capability seam |
| Orchestration | `SlopadEngine` | Public `EditorSession` and editor semantics across owners |
| Canonical owner | `SlopadEditorModel` | Document, selection, commands, transactions, history |
| Derived owner | `SlopadBlockLayout` | Visibility, block geometry, hit/reveal facts, caches, height index |
| Format syntax | `SlopadMarkdownInputRules` | Internal immutable bounded typed-input patterns |
| Format codec | `SlopadMarkdown` | Opt-in stateless whole-document decode and encode |
| Contracts | `SlopadCoreModel` | Public vocabulary and genuine package cross-target contracts |
| Storage | `SlopadDataStructure` | Editor-independent data structures |

The dependency graph enforces four important absences:

- `SlopadEditorModel` and `SlopadBlockLayout` do not import each other;
  `EditorSession` coordinates them.
- `SlopadAppKitTextKit` does not import the engine. Runtime calls arrive through
  `BlockTextLayoutProtocol` capabilities defined in `SlopadCoreModel`.
- `SlopadMarkdown` does not import the engine. A caller explicitly decides when decoded
  block inputs enter a document transaction.
- `SlopadAppKit` and `SlopadSwiftUI` add no second controller, Session, document, or cache.

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
| Platform runtime | `SlopadAppKitUI` | responder, native marked range, scroll position, overlay widgets | Must converge on Session facts without becoming semantics |
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

| Interaction | Producer-to-consumer path | Invariant |
| --- | --- | --- |
| Typing/IME | AppKit callback → `SlopadAppKitUI` → `EditorSession.handleInput` → model transaction → layout invalidation → snapshot → synchronized native surface | Composition is a Session overlay until commit; canonical selection stays in canonical coordinates |
| Text pointer selection | AppKit point → Session pointer event → `SlopadBlockLayout` block hit → text backend grapheme hit → Session selection transition → snapshot | Backend returns facts; Session owns selection meaning |
| Block selection/drag | AppKit gutter/body routing → Session runtime preview → layout drop/reveal geometry → model move transaction on successful drop | Preview is runtime state; only the final valid drop mutates the tree |
| Slash command | Model typed-`/` rule → Session query/source runtime → snapshot anchor/catalog → AppKit overlay → Session CAS apply → one model transaction | Query/menu state is not canonical; `/query` deletion and kind change form one undo step |
| Rendering/scroll | AppKit viewport → `EditorSession.render` → block visibility/layout → coherent text backend facts → render snapshot → AppKit surface sync | Only visible projection is rendered; it is not a persistence source |
| Persistence | model semantic change → Session committed revision → host callback → on-demand `documentSnapshot` | Revision is Session-local and signals when to read; it is not a storage revision |
| Reviewed replacement | context snapshot → external review → complete patch → Session epoch/revision/selection CAS → model validation/replacement → layout/runtime invalidation | A changed post-image is one transaction; stale, invalid, or composing sources fail without partial mutation |
| Markdown import/export | caller → `SlopadMarkdown` → fresh `[EditorBlockInput]` or deterministic text → optional Session patch | Codec AST never crosses its target and no conversion is implicit |

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
| Ordinary macOS app | `SlopadAppKit` | document storage policy, app chrome, lifecycle | raw TextKit graph, model/layout internals |
| SwiftUI app | `SlopadSwiftUI` | mount/unmount, document identity, bindings, persistence timing | controller bypass or a second runtime |
| Complete custom platform adapter | `SlopadEngine` plus its own backend | native callback translation, drawing, focus, scroll coherence | direct model/layout coupling |
| Markdown caller | `SlopadMarkdown` and optionally `SlopadEngine` | explicit import/export timing and failure UX | parser AST retention or partial success |
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

`SlopadSwiftUI` packages the mount → edit → observe → flush → replace → unmount lifecycle.
It guards document identity, filters committed changes, bridges focus, and flushes
composition before persistence without re-exporting the controller.

## Markdown Boundaries

Markdown has two deliberately separate entry points:

- `SlopadMarkdownInputRules` contains parser-free bounded prefix/inline patterns linked
  into ordinary editing. `SlopadEditorModel` owns trigger classification, candidate
  evaluation, canonical mutation, and undo.
- `SlopadMarkdown` is an opt-in whole-document codec. It accepts/returns public
  `[EditorBlockInput]` values and depends on `swift-markdown`; it owns no editor runtime.

Decode and encode are stateless and fail closed with nonempty typed diagnostics. Decode
creates fresh IDs. The supported round-trip contract preserves canonical tree/content
semantics rather than source spelling or identity. Parser AST types remain internal:
only `Sources/SlopadMarkdown` may use `internal import Markdown`.

The codec is not a plugin registry, persistence choice, or paste fallback. Callers decide
when to import/export and how to present unsupported input. See
[ADR 0013](../ADR/0013-markdown-format-boundary.md).

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
