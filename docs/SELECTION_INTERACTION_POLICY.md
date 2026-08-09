# Selection Interaction Policy

Status: implemented; installed-IME/manual visual verification remains

Decided: 2026-08-09

Architecture decision: [ADR 0014](../ADR/0014-latch-selection-mode-and-support-cross-block-text.md)

Visual companion: [Selection interaction map](selection-interaction-map.html)

This is the implementation-facing source of truth for caret, text selection, cross-block
text selection, and block selection. Current source and tests are authoritative for the
implemented behavior; this document records the policy they implement and the remaining
manual verification boundary.

## Evidence Labels

| Label | Meaning |
| --- | --- |
| **Target** | Normative Slopad behavior agreed for implementation |
| **Notion observed** | Reproduced directly in the connected Notion Playground on 2026-08-09 |
| **User confirmed** | Supplied screenshots or an explicit product rule from this design review |
| **Implemented** | Current Slopad source and owner-level tests implement the rule |
| **Settled decision** | Product choice fixed during this review and normative for implementation |

Notion is reference evidence, not Slopad's state owner. Pointer-origin behavior could not
be driven reliably by browser automation inside Notion's contenteditable surface, so
those rows use the supplied screenshots and explicit user confirmation. Keyboard,
clipboard, formatting, deletion, nesting, Escape, and Cmd-A rows were exercised directly.
IME composition could not be validated faithfully through browser automation.

## State Vocabulary

| Code | Canonical state | Meaning |
| --- | --- | --- |
| `I` | `.inactive` | No caret and no selection |
| `C` | `.caret(TextPosition)` | Collapsed text insertion position |
| `T1` | `.text(TextSelection)` | Non-collapsed text range whose endpoints share one block |
| `TN` | `.text(TextSelection)` | Non-collapsed or separator-only text range whose endpoints are in different blocks |
| `B` | `.blocks(BlockSelection)` | Explicit structural selection of blocks |
| `M` | Session composition lifecycle | Marked-text lifecycle layered over `C`, `T1`, or `TN`; not a sixth canonical selection mode |

`TextSelection` always retains its directional `anchor` and `focus`. Commands normalize
them to canonical DFS order only when they need an earlier and later endpoint. A global
integer document position is forbidden.

Focus and caret presentation do not add canonical states. A focused `C` uses AppKit's
native caret blink cadence; `T1`, `TN`, and `B` show selection feedback rather than a
blinking caret. Window/editor focus loss hides the caret but does not implicitly rewrite
canonical selection. During `M`, callback updates replace the actual editing content while
Session keeps one composition/history group and defers the externally committed revision
until commit. Native marked-range presentation remains runtime state and is not persisted.

## Non-Negotiable Invariants

1. **Pointer-down chooses the mode.** Text lane creates `C/T1/TN`; gutter or structural
   margin creates `B`. The mode cannot change before pointer-up.
2. **Crossing a block does not mean selecting a block.** Text selection continues to the
   exact text position under the pointer or reached by keyboard navigation.
3. **Empty blocks are logically crossed but not painted as text.** They participate in
   Escape, deletion, structured copy, and range normalization, while producing no blue
   glyph rectangle.
4. **Direction is retained; mutation is direction-independent.** Reverse drag changes
   anchor/focus, not the document result.
5. **One action, one history result.** A replacement, delete, cut, Enter, or formatting
   command spanning blocks produces one transaction. Composition may receive several
   native updates, but they form one history group and publish one committed revision when
   committed.
6. **Rendering is viewport-bounded.** Canonical state stores two endpoints. Per-frame work
   derives only visible block-local ranges; full-span traversal is reserved for commands.
7. **Input is language-independent.** Direct Latin input, committed Korean input, and any
   other committed text use the same replacement policy. IME differs only in lifecycle.

## Pointer Origin Policy

The AppKit adapter classifies the physical hit once, then sends a typed begin event.
Session latches the corresponding runtime gesture.

| Pointer-down origin | Initial state | Drag result | Empty-space rule | Evidence |
| --- | --- | --- | --- | --- |
| Glyph or text line fragment | `C` at exact hit | `T1` or `TN` to exact focus position | Empty blocks crossed later have no text rect | Target, user confirmed |
| Empty editable block, click without drag | `C(block, 0)` | — | The empty block remains editable | Target, Notion observed |
| Text lane with no glyph-bearing block at the start point | Direction-pending text gesture | When direction is known, use the nearest non-empty text edge in that direction as the anchor | Empty blocks/gaps are skipped visually but stay in the logical crossed span | Implemented, user confirmed |
| Left gutter or left/right structural margin | `B` anchored at the resolved block | Extend `B` in visible canonical order | Empty blocks receive normal block-selection chrome | Target, user confirmed |
| Any latched drag during autoscroll | Preserve its current mode | Extend only that mode | Offscreen traversal must not materialize the whole span for rendering | Target |

A drag that begins on text never threshold-converts to `B`. A drag that begins in a
structural margin never becomes `T1/TN` after crossing characters.

## State and Action Matrix

The table states the fully settled target. A remaining evidence limitation marks a
validation requirement, not an unresolved product choice.

| Action | `I` | `C` | `T1` | `TN` | `B` |
| --- | --- | --- | --- | --- | --- |
| Click text | `C` at hit | Move `C` | Collapse to `C` at hit | Collapse to `C` at hit | Exit structural mode; `C` at hit |
| Double-click text | `T1` word; repeat same word selects full block text | Same | Replace with clicked word/full text | Replace with clicked word/full text | Exit structural mode; clicked word/full text |
| Click structural margin/block affordance | Single-block `B` | Single-block `B` | Single-block `B` | Single-block `B` | Replace with the clicked single-block `B` or begin its drag affordance |
| Drag from text lane | `T1/TN` | `T1/TN` from the new anchor | New `T1/TN` | New `T1/TN` | Exit structural mode; new `T1/TN` |
| Drag from structural margin | `B` | `B` | `B` | `B` | New/extended `B`; mode remains latched |
| Pointer-up / drag cancel | Preserve canonical state; clear only matching runtime | Same | Same | Same | Preserve `B`; clear selection/reorder preview runtime |
| Arrow without Shift | No-op | Move one native step, crossing block boundaries | Collapse toward the directional range edge; next key moves | Same, using logical range edge | Up/Down moves the structural range; Left/Right collapses to its directional edge block |
| Shift+Left/Right | No-op | Preserve anchor, move focus one character | Extend/shrink by one character | Extend/shrink across separator and glyph steps | Shift-Right exits `B` into `T1` selecting the first character of the canonical first selected block; Shift-Left is a no-op |
| Shift+Up/Down | No-op | Preserve anchor, move focus to the native visual destination | Same; do not select a whole block at once | Same across adjacent blocks with preferred horizontal position | Extend structural selection in visible order |
| Word / text-boundary navigation | No-op | Move by native word or current-block boundary, then cross blocks when that command defines it | Collapse or extend using the same anchor/focus rule | Continue from `focus`; never convert to `B` | Structural navigation only; text commands do not reinterpret `B` |
| Escape | No-op | `B` containing the caret block | `B` containing the selected block | `B` containing every logically touched block, including empty ones | `I` |
| Clear-selection host action | No-op | `I` | `I` | `I` | `I` |
| Cmd-A | `B(all)` | Full current-block text; empty block goes directly to `B(all)` | Full current-block text, then `B(all)` if already full | Full text of the already-touched block span, then `B(all)` if already full | `B(all)`; no-op if already all |
| Committed text | No-op | Insert, then `C` after input | Replace range, then `C` | Cross-block replace, then `C` in the earlier endpoint survivor | No-op; printable input does not leave structural selection |
| Plain-text paste | No-op | Insert literally, then `C` after input | Replace range literally, then `C` | Cross-block replace literally, then `C` in the earlier endpoint survivor | Replace selected roots with paragraph content; do not auto-decode Markdown |
| Structured paste | No-op | Insert with the source-selection merge rules below | Same | Same | Replace selected roots with the copied roots/subtrees |
| IME begin/update/commit/cancel | No-op | Native marked-text lifecycle; one history group | Same replacement semantics | Apply live replacement through the native composition lifecycle and group the session as one undo action | No-op, matching other printable input |
| Backspace / Delete | No-op | Native character or block-boundary deletion | Delete range | Delete normalized span and merge endpoints | Delete selected block roots; deleting every block leaves one empty paragraph with `C(0)` |
| Enter | No-op | Existing block split/list-empty behavior | Delete selection, then split at the collapsed position | Cross-block replace with empty text, then run the existing split behavior | Exit `B` and place `C` at the canonical first selected block's end |
| Shift-Enter | No-op | Insert soft line break | Replace range with soft line break | Cross-block replace with a soft line break | No-op; preserve `B` |
| Copy | No-op | No-op | Plain text and structured text-fragment payload | Same across all fragments and relative structure | Whole selected roots/subtrees plus a plain-text projection |
| Cut | No-op | No-op | Copy then delete in one transaction | Copy then cross-block delete in one transaction | Copy then structural delete in one transaction |
| Inline style | No-op | Toggle stored mark | Apply to selected fragment | Apply to every selected fragment in one transaction | Apply to the complete text of every selected text-capable block; skip atomic blocks; remain `B` |
| Indent / Outdent | No-op | Existing block-local text-indent behavior | Apply to touched block-local lines | Structurally indent/outdent every logically touched block | Structurally indent/outdent selected roots |
| Undo / Redo | Restore history snapshot | Restore document and exact selection snapshot | Same | Same, including anchor/focus direction and affinity | Same |
| Block reorder drag | No-op | No-op | No-op | No-op | Available only from structural selection/drag affordance |

This matrix covers every category in the current `EditorInputEvent` contract: pointer
focus/select/drag/double-click/block range/reorder, text and composition input, deletion,
Enter, Escape, clear, navigation, indent, styles, select-all, clipboard, and history.
`activeTextSelectionChanged` is a native-surface synchronization callback rather than a
separate user action: a genuine local change creates `C/T1` in the focus block, while a
programmatic sync must not collapse canonical `TN` back to its focus-block fragment.

### Escape

Escape is an explicit text-to-structure transition:

```text
C ──Escape──▶ B(current block) ──Escape──▶ I
T1 ─Escape──▶ B(current block) ──Escape──▶ I
TN ─Escape──▶ B(all touched blocks, including empty) ──Escape──▶ I
```

If composition is active, Escape first commits the current marked text using the existing
native contract, then applies the transition to the resulting selection. The host's
`clearSelection` action remains intentionally different: it goes to `I` in one step.

### Cmd-A

Cmd-A expands the current semantic scope rather than always jumping to every block:

```text
non-empty C or partial T1
  └─ Cmd-A → full T1 in that block
               └─ Cmd-A → B(all document blocks)

partial TN over blocks A...D
  └─ Cmd-A → TN from A.start through D.end, preserving direction
               └─ Cmd-A → B(all document blocks)

empty-block C, I, or partial B
  └─ Cmd-A → B(all document blocks)
```

The implementation skips an invisible zero-length `T1` step for an empty caret. A partial
`TN` first expands its touched text span instead of immediately becoming `B(all)`.

### Keyboard Text Extension

Shift navigation never changes a text selection into block selection. The anchor stays
fixed and the focus performs one native movement operation per keypress:

```text
A: abc|     B: |def
       Shift+Right  →  A.end → B.start     (logical separator only, no blue glyph)
       Shift+Right  →  A.end → B.offset 1  ("d" is now painted)
```

Shift-Up/Down first uses the text backend's visual-line destination. At a block boundary,
Session resolves the adjacent block and continues using the preferred horizontal
position. It must not select the adjacent block's entire text as a shortcut.

## Cross-Block Mutation

For a normalized selection from earlier block `A` at offset `a` to later block `B` at
offset `b`, replacing it with text `X` has this document result regardless of drag
direction:

```text
A' = A.prefix(0..<a) + X + B.suffix(b..<end)
caret = TextPosition(A.id, a + X.count)
remove = every fully covered intermediate block and B
```

- `A.id`, `A.kind`, and `A.parentID` survive.
- Prefix marks survive unchanged; inserted marks follow stored/pasted-mark policy; suffix
  marks shift to their new offsets.
- Selecting all text of `A` through all text of `B` and deleting leaves `A` as an empty
  block with `C(A, 0)`.
- The entire operation, including tree repair and selection placement, is one model
  transaction and one undo step.
- Empty intermediate blocks are removed even though they had no painted text rectangle.

Direct Notion evidence confirmed prefix-plus-suffix merging, direction independence, the
earlier block as survivor, empty-survivor behavior, and single-step paste replacement.

### Unselected children of a removed endpoint

Slopad promotes `B`'s unselected children to `B.parentID`. A live Notion test produced a
different result:

```text
before                            after deleting A.end ... B.end
A (root)                          A (root, survives)
B (root, selected text removed)     ├─ B.child.1
  ├─ B.child.1                       └─ B.child.2
  └─ B.child.2
```

Notion reparents those children under the surviving earlier block `A`; Slopad deliberately
does not. Promotion preserves the unselected subtree at the removed endpoint's structural
level and avoids making the surviving text block an implicit new parent. The repair is part
of the same transaction as the range replacement.

## Rendering and Performance Contract

```text
AppKit hit classification
  → Session latched gesture + canonical anchor/focus transition
    → EditorModel stores only EditorSelection
      → Session intersects the range with visible block IDs
        → Text backend resolves block-local rectangles
          → AppKit paints fragments and syncs one focus-block input client
```

Required complexity and ownership:

- Canonical `TN` storage is O(1): two `TextPosition`s.
- A render pass is O(V + G), where `V` is visible blocks examined and `G` is visible
  selection geometry returned. It must not be O(total selected span).
- Endpoint ordering should use an existing or cached canonical DFS rank lookup; do not
  rebuild a full selected-ID array on every pointer move.
- Copy, cut, delete, formatting, and structured payload creation may be O(K), where `K` is
  the canonical affected span, because they run once per command.
- Damage compares previous and next visible fragment projections. Autoscroll discards
  offscreen rectangles rather than retaining one rectangle per selected block.
- Only the focus block is the native text input surface. Cross-block selection rectangles
  are Session render facts; AppKit and TextKit do not gain canonical selection ownership.

The UI benchmark gate must cover forward and reverse text drags across 100, 1,000, and
10,000 blocks, including autoscroll and empty blocks. Correctness gates must assert that
frame work is bounded by visible content while command-time deletion still visits the
complete affected span.

## Engine Contract for High-Level UI

The state matrix is not enough for a floating toolbar, context menu, inspector, link
editor, comment UI, or structured paste surface. Those views must not inspect
`EditorSelection` and reconstruct engine policy independently. They need three different
projections with different costs and owners:

| Projection | Owner | Lifetime and cost | Consumers |
| --- | --- | --- | --- |
| Canonical selection | `SlopadEditorModel` | Persistent editing state; O(1) `TextPosition` endpoints | Commands, history, document context |
| Resolved command span | `SlopadEditorModel`, requested by Session | Ephemeral command/preflight value; may traverse O(K) affected blocks | Delete, replace, format, copy, Enter, indent |
| Visible selection presentation | `EditorSession` coordinating BlockLayout/TextLayout | Viewport-scoped O(V + G) projection | AppKit painting, toolbar geometry facts, accessibility |

Do not turn `EditorSelectedContent` into the live selection owner. It is a public,
review-oriented output projection and currently materializes the complete document order.
Extract one lower-level canonical range resolver, then let review context, clipboard,
mutation, formatting, and command-state aggregation project from it at the cost appropriate
to each use.

### Proposed engine-owned values

The names below are design vocabulary, not permission to make every type public now.
Start `internal` or `package`; widen only when a real host consumer passes ADR 0012's
exposure test.

```swift
// SlopadEditorModel: normalized semantic input to one command.
struct ResolvedTextSpan {
    let selection: TextSelection       // original direction retained
    let start: TextPosition            // canonical earlier endpoint
    let end: TextPosition              // canonical later endpoint
    let fragments: [ResolvedTextFragment]
}

// SlopadEngine: viewport-independent facts for buttons/menus.
struct EditorCommandState {
    let selection: EditorSelection
    let actions: [EditorActionID: EditorActionAvailability]
    let inlineMarks: [InlineMarkKind: EditorToggleState]
    let blockKind: EditorMixedValue<BlockKind>
}

// SlopadEngine snapshot: viewport-dependent facts, never canonical state.
struct EditorSelectionPresentation {
    let visibleFragments: [EditorVisibleTextSelection]
    let focusBlockID: BlockID?
    let visibleBounds: EditorRect?
    let focusRect: EditorRect?
}
```

`EditorActionAvailability` needs at least `unavailable`, `available`, and
`availableAfterCompositionCommit`. Querying availability must not commit composition or
mutate selection. Applying the action revalidates the same policy and may still fail if the
state changed. `EditorToggleState` needs `unavailable`, `off`, `on`, and `mixed` so a
toolbar can render a multi-fragment bold/italic state without guessing.

The existing package-level `EditorCommandResult` already distinguishes `notApplicable`,
selection-only, and document changes. Keep that as the authoritative application result.
Do not create a second command engine for toolbar actions; `AppKitEditorAction` and native
callbacks must converge on the same Session/model command path.

### Query and apply must share one policy

High-level UI requires a preflight/query surface, but it is advisory rather than authority:

```text
selection/document/composition
  → Session command-state query
    → toolbar/menu enablement and mixed-state display

user activates an enabled action
  → synchronized AppKit action
    → Session revalidates current state
      → Model resolves span and commits one transaction
        → update + fresh command state + visible presentation
```

The query and apply paths must call the same owner-level predicates. A switch duplicated in
SwiftUI/AppKit will eventually enable a command the model rejects or hide one it supports.
`perform(_:) != nil` is an application result, not a sufficient command-availability API.

### Geometry facts, not toolbar placement

Session should publish `visibleBounds`, the focus fragment/caret rect, and whether either
endpoint is offscreen. It should not decide whether a bubble toolbar sits above, below, or
beside the range. AppKit owns screen conversion, safe-area/window clamping, animation, and
popover placement. This keeps selection meaning in Session while leaving presentation in
the adapter.

For `TN`, `visibleBounds` is the union of visible selection rectangles only. It must not
allocate rectangles for offscreen blocks merely to center a toolbar. A practical AppKit
anchor preference is focus fragment → nearest visible endpoint → visible union, but that
choice remains adapter policy.

### Command-state cost tiers

A toolbar must not turn every drag update into an O(K) mark scan:

- **Live drag:** publish lightweight mode, endpoint, focus geometry, and O(1) action
  availability. Hide or defer rich formatting state.
- **Pointer-up / stable keyboard selection:** compute mixed inline marks/block kinds once,
  cached by `(document revision, exact selection)`.
- **Command activation:** resolve the complete canonical span and revalidate bounds.
- **Scroll-only update:** recompute visible geometry, not command state or selected content.

Canonical endpoint rank lookup needs a model-owned derived order index or equivalent
package query. `VisibleBlockIndex` may accelerate rendering, but it cannot become the
canonical range authority because future collapsed descendants can be absent from visible
order.

### Clipboard is a plan, not a string query

Replace the one-way `selectedPlainText()` shape with a two-phase boundary:

1. Session builds an `EditorClipboardPlan` containing a plain-text projection plus either
   a partial-text or complete-subtree structured projection.
2. AppKit negotiates `NSPasteboard` types and performs the external write/read.
3. Cut mutates only after the required pasteboard write succeeds. Paste sends a typed
   payload back to Session, which applies one canonical transaction.

The plan is an ephemeral value, not a second document model. The adapter writes a
versioned Slopad pasteboard type together with ordinary plain text. Slopad does not add an
implicit HTML/RTF or Markdown-import path here. Canonical tree repair and insertion belong
to model commands.

### Asynchronous UI needs a selection source token

Synchronous toolbar buttons can act on the current selection. A link editor, comment
composer, AI menu, or delayed paste preview may remain open while the document or
selection changes. Such UI must capture an opaque source that pins Session epoch,
committed revision, and exact selection, then fail closed when stale.

Do not hold the editor selection “locked” merely to keep a popover alive. Do not reuse the
review-specific `EditorDocumentSource` publicly without a concrete consumer; introduce a
narrow selection-action token only when the first asynchronous feature needs it. The
existing slash-command source validation is the behavior pattern.

### Decorations are not local selection

Search matches, comments, spellcheck, AI ranges, and future remote cursors should use a
separate derived decoration projection:

- no caret/input ownership;
- no local `EditorSelection` replacement;
- no undo/history entry for presentation-only changes;
- viewport-bounded geometry through Session/TextLayout;
- stable IDs so AppKit can damage only changed visible decorations.

This separation lets high-level UI add multiple highlighted ranges without teaching the
canonical editor that it has multiple local carets or selections.

### Feature-to-contract map

| High-level UI | Engine facts it consumes | Engine action it sends |
| --- | --- | --- |
| Floating formatting toolbar | command state, mixed marks, visible/focus geometry | typed inline-style/clear-style action |
| Context menu / command palette | action availability and selection summary | existing semantic `AppKitEditorAction` |
| Block handle menu | selected roots, block-kind mixed value, structural availability | kind/indent/delete/reorder command |
| Link editor / comment composer | exact selection source, selected fragments, geometry facts | stale-checked range command |
| Structured copy/paste preview | clipboard plan and supported payload kinds | typed paste payload or cancel |
| Find/search/comments/remote cursors | decoration ranges and visible geometry | separate navigation or annotation action |
| Accessibility | canonical block semantics, selected content summary, visible geometry | the same typed navigation/editing actions |
| Future UIKit selection handles | endpoint geometry and latched gesture mode | the same pointer/selection intents as AppKit |

### Snapshot and callback shape

Built-in AppKit UI should first consume package fields on `EditorSessionSnapshot`:

- `selectionPresentation` for visible fragments and geometry;
- a future P2 `commandState` for availability/mixed values;
- the existing singular `activeTextInput` for native IME/focus synchronization.

If a host-owned SwiftUI toolbar becomes a real supported use case, expose a curated,
viewport-independent command state through `SlopadEditorModel` and a synchronized
controller observation. Do not expose raw TextKit rectangles, BlockLayout, or the complete
Session snapshot. Scroll-dependent floating chrome can remain in the built-in adapter
until a host proves it needs a geometry contract.

### Additional correctness gates

- `EditorSession+RenderDamage` damages changed **visible** fragments by prepared
  visible-order rank without enumerating the offscreen span.
- Native `activeTextSelectionChanged` callbacks caused by surface synchronization must not
  collapse canonical `TN` to the focus block's local fragment.
- Command-state and action tests must assert `available` implies the same unchanged state
  is accepted by apply; apply still revalidates after state changes.
- Toolbar focus transfer must not silently clear selection or commit composition merely
  because the user opened a menu. The selected action may explicitly use the synchronized
  commit-before-action boundary.
- Accessibility and clipboard selected text must use the same canonical fragment resolver
  as mutation, including empty logical blocks and direction-independent normalization.

## Clipboard Contract

Text selection and block selection need different structured payloads:

| Selection | Structured payload | Plain-text projection |
| --- | --- | --- |
| `T1/TN` | Partial endpoint fragments, complete intermediate fragments, source kind/parent information, relative hierarchy, and rebased inline marks | Human-readable text; do not blindly join every block with `"\n"` |
| `B` | Deduplicated selected roots and each complete subtree in canonical DFS order | Serialize whole blocks by kind |

Notion used a partial multi-text payload for `TN` and a different whole-block payload for
`B`. Slopad follows its open-edge merge behavior while retaining its own canonical model:

- A structured `B` payload pasted at a block boundary inserts complete copied blocks.
- The same payload pasted inside destination text absorbs the first copied block into the
  destination prefix and the last into the destination suffix. Their wrapper kinds are
  discarded; complete blocks strictly between them retain their kinds and subtrees.
- A `T1/TN` payload always behaves as a text slice. Partial first/last fragments merge into
  the destination edges and lose their source wrapper kinds. Complete intermediate blocks
  and atomic blocks retain their structure. Even a fully covered endpoint keeps text-slice
  behavior when the source mode was text selection.
- A structured paste mints fresh `BlockID`s and preserves only relative hierarchy.

Copy writes the versioned Slopad structured representation and an ordinary plain-text
fallback. Paste chooses a valid supported Slopad representation first, then plain text.
Invalid, unsupported-version, or oversized structured data fails closed to plain text.
External plain text is inserted literally and is never auto-decoded as Markdown; Markdown
conversion remains an explicit import operation.

Structured paste must remain an edge format negotiated by the adapter and applied through
one canonical Session/model transaction. It must not become a second document model.

## Implementation Closure

The old-policy sites were migrated under their existing owners:

| Area | Implemented behavior |
| --- | --- |
| [`EditorSession+TextPointerDragInput.swift`](../Sources/SlopadEngine/Session/TextInteraction/EditorSession+TextPointerDragInput.swift) | Latches text mode, hit-tests the current block, and resolves an empty-origin drag from the nearest non-empty edge in its direction. |
| [`EditorSession+VerticalMovementInput.swift`](../Sources/SlopadEngine/Session/Navigation/EditorSession+VerticalMovementInput.swift) | Extends text by one visual destination across block boundaries without converting to `B`. |
| [`EditorSession+ActiveTextSelection.swift`](../Sources/SlopadEngine/Session/TextInteraction/EditorSession+ActiveTextSelection.swift) | Keeps one focus-block native input descriptor while canonical `TN` retains both endpoints. |
| [`EditorSession+Rendering.swift`](../Sources/SlopadEngine/Session/EditorSession+Rendering.swift) | Projects visible block-local text ranges and atomic block tint from prepared visible-order ranks. |
| [`EditorSession+RenderDamage.swift`](../Sources/SlopadEngine/Session/EditorSession+RenderDamage.swift) | Computes selection damage only from visible ranks; it no longer materializes the full `TN` span per pointer update. |
| [`EditorSession+ClipboardWritePlan.swift`](../Sources/SlopadEngine/Session/Selection/EditorSession+ClipboardWritePlan.swift) | Produces versioned text-slice or block-subtree payloads and a kind-aware plain fallback. |
| [`EditorSession+CommandInput.swift`](../Sources/SlopadEngine/Session/InputRouting/EditorSession+CommandInput.swift) | Routes `TN` typing, deletion, Enter, formatting, indentation, Escape, Cmd-A, and structured paste through shared model semantics. |
| [`EditorModel+TextContentCommands.swift`](../Sources/SlopadEditorModel/Command/EditorModel+TextContentCommands.swift) | Replaces normalized cross-block spans, preserves the earlier endpoint, promotes removed-endpoint descendants, and records one transaction. |
| [`EditorModel+StructuredPasteCommands.swift`](../Sources/SlopadEditorModel/Command/EditorModel+StructuredPasteCommands.swift) | Applies fresh-ID structured forests using root-aware open-edge merging while preserving endpoint and middle subtrees. |
| [`AppKitEditorViewController.swift`](../Sources/SlopadAppKitUI/AppKitEditorViewController.swift) | Classifies the origin once, keeps text/block drag modes distinct, and continues text selection during autoscroll. |
| [`AppKitActiveInputController.swift`](../Sources/SlopadAppKitUI/AppKitActiveInputController.swift) | Negotiates typed plus plain clipboard representations, fail-closed paste fallback, and cut-after-write-success. |
| Session/AppKit tests and UI benchmark | Cover forward/reverse `TN`, empty and atomic blocks, native text/gutter event paths, autoscroll, structured clipboard, IME commit/cancel, exact undo, and 100/1,000/10,000-block projection. |

`ResolvedTextSpan` is the shared command-time owner used by mutation, formatting,
clipboard, selection escalation, and Assistant projection. Render-time code deliberately
uses prepared visible-order ranks instead of that full-span traversal.

## Settled Implementation Decisions

| ID | Target rule |
| --- | --- |
| `D1` | Promote unselected children of removed endpoint `B` to `B.parentID`. |
| `D2` | Deleting every selected block leaves the first selected block as an empty paragraph with `C(0)`. |
| `D3` | Printable/IME input is ignored in `B`; paste is intentional replacement; inline marks cover all selected text-capable blocks and leave `B` active. |
| `D4` | `TN` Enter and Shift-Enter are delete-then-split and delete-then-soft-break; `B` Enter enters text at the first block's end and `B` Shift-Enter is a no-op. |
| `D5` | Clipboard uses typed Slopad text-slice/block-subtree payloads plus plain text, with the Notion-style open-edge rules above and no automatic Markdown decode. |
| `D6` | Undo/redo restores exact selection mode, anchor/focus direction, offsets, and affinity. |
| `D7` | `B` Shift-Right enters first-character `T1`, Shift-Left is a no-op; `TN` indent/outdent acts on every touched block; atomic and collapsed subtree content participates logically and uses block tint when it has no text geometry. |

### Implemented result — 2026-08-10

- D1–D7 are implemented in `EditorModel`/`EditorSession`; the AppKit adapter owns only
  physical hit classification, native callbacks, pasteboard negotiation, drawing, and
  autoscroll.
- `TN` remains two `TextPosition` endpoints. Visible selection and redraw damage use only
  prepared visible-order ranks; the 10,000-block regression tests assert viewport-bounded
  projection.
- Clipboard copy writes `com.hot666666.slopad.clipboard.v1` and `.string`. Structured
  paste validates version/shape/size at the edge, mints fresh IDs, preserves relative
  subtrees and marks, and applies one model transaction.
- Recorded focused runs pass: `SlopadEngineTests` 440 tests and `SlopadAppKitUITests` 90
  tests. The AppKit target itself is still intermittently affected by the teardown runner
  failure described below, so this is recorded passing evidence rather than a claim that
  every rerun is stable. The deterministic UI benchmark covers forward/reverse text
  selection at 100, 1,000, and 10,000 blocks with empty blocks mixed in.
- Installed input-source candidate-window behavior and visual inspection in
  `SlopadDebugApp` remain manual evidence boundaries. The repository-wide Swift Testing
  helper can still terminate with an AppKit `NSWindow` teardown signal 11, most often
  when AppKit and SwiftUI suites share one process and occasionally in a focused AppKit
  rerun.
- The production `SlopadDebugApp` state harness passes all 18 scenarios, including the
  real cross-block text drag and viewport-derived down/up reveal boundaries.
- Collapsed subtrees remain a P4 feature because Slopad has no collapse state yet. D7 is
  the forward-compatible rule that feature must obey. Shared toolbar mixed-value and
  availability projection remains P2 and is not a second selection owner.

Recorded `cross-block-selection-drag` benchmark after viewport-bounded damage projection:

| Blocks | Average FPS | Average frame | Average selection operation |
| ---: | ---: | ---: | ---: |
| 100 | 53.6 | 18.672 ms | 12.648 ms |
| 1,000 | 48.0 | 20.842 ms | 15.474 ms |
| 10,000 | 41.3 | 24.225 ms | 17.366 ms |

The same 10,000-block run before the visible-rank damage change measured 19.6 FPS,
51.131 ms average frame time, and 34.831 ms average selection-operation time. These are
local deterministic benchmark records, not a universal hardware threshold.

## Implementation Verification Plan

Evidence is accumulated by owner and by the real producer-to-consumer path. A lower-layer
test cannot substitute for a native callback, visual, or performance claim.

### Gate 0 — policy artifacts before executable work

- ADR 0014, this policy, the HTML map, and ROADMAP must contain the same D1–D7 outcomes.
- No product cell may remain marked `Decision needed`, `D1`…`D7`, or `unresolved`.
- Validate relative links, unique matrix row IDs, HTML controls, script syntax, and narrow
  responsive rendering. Record visual inspection separately from source checks.

### Gate 1 — canonical owner and transactions

Focused `SlopadEditorModelTests` must cover forward and reverse `TN` for replacement,
Backspace/Delete, Enter, Shift-Enter, formatting, indent/outdent, and undo/redo. Assertions
must include:

- exact document DFS post-image, surviving `BlockID`/kind/parent, and fresh pasted IDs;
- promotion of removed endpoint children to the removed endpoint's parent;
- one transaction and one undo step per action;
- exact restored selection mode, anchor/focus direction, offsets, and affinity;
- empty endpoints/intermediate blocks, nested parents, atomic blocks, and all-content delete.

### Gate 2 — Session semantics and bounded projection

Focused `SlopadEngineTests` must exercise every changed matrix row through
`EditorSession.handleInput`, including pointer-origin latching, separator-only keyboard
steps, Escape, staged Cmd-A, `B` printable/IME no-op, `B` Enter/Shift-Enter, and typed
clipboard payload routing. Rendering tests must prove that `TN` stores only endpoints and
projects only visible block-local ranges while command-time operations still visit the
complete logical span.

### Gate 3 — AppKit adapter and pasteboard negotiation

Focused `SlopadAppKitUITests` must enter through the production adapter and assert:

- text-lane drag remains `T1/TN`; structural-margin drag remains `B`;
- focus-block native selection synchronization does not collapse canonical `TN`;
- copy writes both the versioned Slopad type and `.string`;
- paste prefers a valid supported Slopad payload, falls back on invalid/newer/oversized
  data, and never auto-decodes plain Markdown-looking text;
- a failed required pasteboard write prevents Cut deletion;
- caret blink is visible only for a focused idle `C`, stops during composition/input, and
  resumes afterward using the native AppKit cadence.

### Gate 4 — native callback and visual behavior

Build and run `SlopadDebugApp`. The native callback smoke must use synthesized `NSEvent`
delivery through `NSWindow.sendEvent(_:)` and real `NSTextInputClient` callbacks rather
than calling semantic handlers directly. Manually inspect forward/reverse cross-block
drag, empty gaps, autoscroll, Escape/Cmd-A, clipboard round trips, caret blink, and Korean
composition/cancel. The marked-text smoke proves callback handling but is not evidence for
the installed IME candidate window or physical keyboard path; report that manual boundary.

### Gate 5 — performance and redraw

Build `SlopadUIBenchmarkApp` and add deterministic forward/reverse cross-block drag plus
autoscroll scenarios at 100, 1,000, and 10,000 blocks, including empty blocks. Capture the
benchmark environment and compare repeated runs. Acceptance requires:

- canonical selection storage independent of span length;
- render/damage work bounded by visible blocks and returned geometry;
- no retained rectangle or selected-ID array proportional to the offscreen selected span;
- no material regression in existing selection, scroll, and mixed-document scenarios.

### Gate 6 — repository and downstream completion

After the executable diff is stable, run the canonical and affected-surface gates from
[Testing](TESTING.md):

```sh
swift test --quiet
git diff --check
swift build --product SlopadAppKit --quiet
swift build --product SlopadAppKitTextKit --quiet
swift build --product SlopadAppKitUI --quiet
swift build --product SlopadDebugApp --quiet
swift build --product SlopadUIBenchmarkApp --quiet
swift build --package-path Fixtures/DownstreamAppKitHost --product DownstreamAppKitHost --quiet
```

Completion requires a stable diff review after the tests, fixes for actionable findings,
and a re-review of the final diff. Report unit, native callback, visual/manual, benchmark,
and downstream-build evidence as separate claims.

## Executed Implementation Order From the Settled Policy

1. Add owner-level canonical fragment/range helpers and cross-block replacement
   transactions with tree-repair tests.
2. Replace pointer threshold conversion and vertical Shift conversion with latched text
   navigation, including forward/reverse and empty-block tests.
3. Add the viewport-bounded selection projection, visible-fragment damage, and focus-block
   native input contract.
4. Route delete, paste, Enter, formatting, Escape, Cmd-A, and composition through the
   shared range semantics. Shared command availability/mixed-state derivation stays P2
   until the toolbar becomes its first real consumer.
5. Add clipboard-plan negotiation and kind-aware plain/structured serialization.
6. Add built-in high-level UI only against the shared snapshot/action contracts; add a
   public host projection only when its first real consumer exists.
7. Prove the real AppKit path in `SlopadDebugApp`, then run the 100/1,000/10,000-block UI
   benchmark gates before claiming completion.
