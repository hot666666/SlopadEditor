# Selection Interaction Policy

Status: non-IME policy implemented; live cross-block IME replacement is not implemented or
product-verified. Apple built-in Korean 2-set installed-IME delivery is also not yet proven.

Decided: 2026-08-09

Architecture decision: [ADR 0014](../ADR/0014-latch-selection-mode-and-support-cross-block-text.md)

Visual companion: [Selection interaction map](selection-interaction-map.html)

This is the implementation-facing source of truth for caret, text selection, cross-block
text selection, and block selection. Current source and tests are authoritative for the
implemented behavior. The IME rows remain the decided target, but installed input-method
events currently do not reach the composition consumer in product use; direct
`setMarkedText` tests prove the callback contract only, not installed-IME delivery.

## Document Map

This file contains three kinds of material with different authority. Read the one that
answers your question; do not treat design rationale as a contract.

| Sections | Kind | Authority |
| --- | --- | --- |
| Evidence Labels → Rendering and Performance Contract | **Normative contract** | What the implemented policy requires. `docs/ARCHITECTURE.md` cites this range. |
| Engine Contract for High-Level UI | **Design rationale, partly superseded** | Explains *why* the projections are split. Its type sketches predate implementation; Implementation Closure names what actually shipped. |
| Clipboard Contract → Settled Implementation Decisions | **Normative contract** | Payload rules and `D1`–`D7`. |
| Implementation Verification Plan → Executed Implementation Order | **Completed gate record** | Historical evidence of how the work was verified, not a standing work order. |

When a type name here disagrees with source, source wins and this document is the defect.

## Evidence Labels

| Label | Meaning |
| --- | --- |
| **Target** | Normative SlopadEditor behavior agreed for implementation |
| **Notion observed** | Reproduced directly in the connected Notion Playground on 2026-08-09 |
| **User confirmed** | Supplied screenshots or an explicit product rule from this design review |
| **Implemented** | Current SlopadEditor source and owner-level tests implement the rule |
| **Settled decision** | Product choice fixed during this review and normative for implementation |

Notion is reference evidence, not SlopadEditor's state owner. Pointer-origin behavior could not
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
canonical selection. The decided future `M` target replaces actual editing content during the
callback lifecycle and groups its history. The current foundation instead keeps a Session
composition overlay, projects it through layout, and mutates canonical content once on
commit. Native marked-range presentation remains runtime state and is not persisted.

When the future live target replaces the overlay, its editing content is transaction-local
until close: public `documentSnapshot` continues to expose the last published committed
document and revision, not provisional marked text. A changed close publishes the new
snapshot with its one committed revision; cancel or exact no-op restoration publishes neither.

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
   command spanning blocks produces one transaction. In the future IME target, several
   native updates would form one live history group; closure would record one history item
   only when the final canonical document, selection, or stored marks differ from the
   pre-composition state, and would publish one committed revision only for a document
   change. The current implementation does not apply those updates to canonical content:
   Session projects an effective-document overlay and commits it through one model
   transaction. Exact overlay cancellation closes runtime composition without history or
   revision and preserves the existing redo branch.
6. **Rendering is viewport-bounded.** Canonical state stores two endpoints. Per-frame work
   derives only visible block-local ranges; full-span traversal is reserved for commands.
7. **Input is language-independent.** Direct Latin input, committed Korean input, and any
   other committed text use the same replacement policy. The future IME target differs only
   in lifecycle; the current overlay implementation is not that live-replacement target.

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
| IME begin/update/commit/cancel — **future target, implementation blocked** | Future: no-op | Future: live marked-text lifecycle grouped as one history session | Future: same live replacement semantics | Future: live cross-block replacement grouped as one undo action | Future: no-op, matching other printable input |
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

SlopadEditor promotes `B`'s unselected children to `B.parentID`. A live Notion test produced a
different result:

```text
before                            after deleting A.end ... B.end
A (root)                          A (root, survives)
B (root, selected text removed)     ├─ B.child.1
  ├─ B.child.1                       └─ B.child.2
  └─ B.child.2
```

Notion reparents those children under the surviving earlier block `A`; SlopadEditor deliberately
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

> **Status: design rationale. Names here are pre-implementation sketches.**
> The projection split, cost tiers, and ownership arguments below remain correct and
> normative. The Swift declarations are the vocabulary used while designing P2 and were
> not updated as the work landed. For shipped names and files, read
> [Implementation Closure](#implementation-closure); for shipped shapes, read the source.

The state matrix is not enough for a floating toolbar, context menu, inspector, link
editor, comment UI, or structured paste surface. Those views must not inspect
`EditorSelection` and reconstruct engine policy independently. They need three different
projections with different costs and owners:

| Projection | Owner | Lifetime and cost | Consumers |
| --- | --- | --- | --- |
| Canonical selection | `SlopadEditorDocumentModel` | Persistent editing state; O(1) `TextPosition` endpoints | Commands, history, document context |
| Resolved command span | `SlopadEditorDocumentModel`, requested by Session | Ephemeral command/preflight value; may traverse O(K) affected blocks | Delete, replace, format, copy, Enter, indent |
| Visible selection presentation | `EditorSession` coordinating BlockLayout/TextLayout | Viewport-scoped O(V + G) projection | AppKit painting, toolbar geometry facts, accessibility |

Do not turn `EditorSelectedContent` into the live selection owner. It is a public,
review-oriented output projection and currently materializes the complete document order.
Extract one lower-level canonical range resolver, then let review context, clipboard,
mutation, formatting, and command-state aggregation project from it at the cost appropriate
to each use.

### Engine-owned values

These three values shipped as `package` types, matching the design intent that they stay
below the host contract. Widen only when a real host consumer passes ADR 0012's exposure
test; Epic #67 found no such consumer for command state.

```swift
// SlopadEditorDocumentModel: normalized semantic input to one command.
// Sources/SlopadEditorDocumentModel/Selection/ResolvedTextSpan.swift
package struct ResolvedTextSpan: Sendable {
    package let selection: TextSelection   // original direction retained
    package let start: TextPosition        // canonical earlier endpoint
    package let end: TextPosition          // canonical later endpoint
    package let blockIDs: [BlockID]        // canonical DFS span, not a flat coordinate
    package let fragments: [ResolvedTextFragment]
}

// SlopadEditorEngine: viewport-independent facts for buttons/menus.
// Sources/SlopadEditorEngine/Session/CommandState/EditorCommandState.swift
package struct EditorCommandState: Hashable, Sendable {
    package let selectionMode: EditorCommandSelectionMode
    package let detail: EditorCommandStateDetail
    package let clearInlineStylesAvailability: EditorActionAvailability
    package let blockKind: EditorMixedValue<BlockKind>

    // Accessor inputs, not consumer-readable facts.
    let inlineStyleAvailability: EditorActionAvailability
    let inlineStyles: [BlockContent.InlineMark.Kind.CaseIdentity: EditorToggleState]
    let indentBlocksAvailability: EditorActionAvailability
    let outdentBlocksAvailability: EditorActionAvailability
}

// SlopadEditorEngine snapshot: viewport-dependent facts, never canonical state.
// Sources/SlopadEditorEngine/Session/EditorSelectionPresentation.swift
package struct EditorSelectionPresentation: Sendable {
    package let visibleTextSelections: [EditorVisibleTextSelection]
    package let visibleBlockSelectionIDs: Set<BlockID>
    package let visibleBounds: EditorRect?   // visible, viewport-clipped geometry only
    package let focusRect: EditorRect?
    package let isAnchorVisible: Bool
    package let isFocusVisible: Bool
}
```

The design sketch proposed a generic `actions: [EditorActionID: EditorActionAvailability]`
map and an `inlineMarks: [InlineMarkKind: EditorToggleState]` map. Neither `EditorActionID`
nor `InlineMarkKind` exists: availability shipped as named per-command fields, and marks are
keyed by `BlockContent.InlineMark.Kind.CaseIdentity`. Named fields keep the closed command
set compiler-checked, which an open ID map would not.

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

1. Session builds a write plan containing a plain-text projection plus either a
   partial-text or complete-subtree structured projection.
2. AppKit negotiates `NSPasteboard` types and performs the external write/read.
3. Cut mutates only after the required pasteboard write succeeds. Paste sends a typed
   payload back to Session, which applies one canonical transaction.

This shipped as `EditorSession.clipboardWritePlan()` in
[`EditorSession+ClipboardWritePlan.swift`](../Sources/SlopadEditorEngine/Session/Selection/EditorSession+ClipboardWritePlan.swift),
returning `EditorClipboardWritePlan` — a versioned `EditorClipboardPayload` plus its
`plainText` fallback. The payload's structured content is
`.textSlice(EditorClipboardTextSlice)` or `.blockSubtrees(EditorClipboardBlockSubtrees)`,
declared in
[`EditorClipboardPayload.swift`](../Sources/SlopadCoreModel/Clipboard/EditorClipboardPayload.swift).
There is no type named `EditorClipboardPlan`.

The plan is an ephemeral value, not a second document model. The adapter writes a
versioned SlopadEditor pasteboard type together with ordinary plain text. SlopadEditor does not add an
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
| Todo checkbox | per-block todo action availability/state and exact block target | typed toggle-todo action for that block |
| Context menu / command palette | action availability and selection summary | existing semantic `AppKitEditorAction` |
| Block handle menu | selected roots, block-kind mixed value, structural availability | kind/indent/delete/reorder command |
| Link editor / comment composer | exact selection source, selected fragments, geometry facts | stale-checked range command |
| Structured copy/paste preview | clipboard plan and supported payload kinds | typed paste payload or cancel |
| Find/search/comments/remote cursors | decoration ranges and visible geometry | separate navigation or annotation action |
| Accessibility | canonical block semantics, selected content summary, visible geometry | the same typed navigation/editing actions |
| Future UIKit selection handles | endpoint geometry and latched gesture mode | the same pointer/selection intents as AppKit |

### Snapshot and callback shape

Built-in AppKit UI is P2's first command-state consumer. It should first consume package
fields on `EditorSessionSnapshot`:

- `selectionPresentation` for visible fragments and geometry;
- a future P2 `commandState` for availability/mixed values;
- the existing singular `activeTextInput` for callback-contract composition/focus
  synchronization. This does not prove installed-IME delivery.

`EditorSession` owns the viewport-independent command-state derivation and revalidates every
action against current state; `EditorModel` remains the canonical mutation owner. If a
host-owned SwiftUI toolbar becomes a real supported use case, expose a curated Session-backed
observation only after it passes ADR 0012. Do not expose raw TextKit rectangles, BlockLayout,
or the complete Session snapshot. Scroll-dependent floating chrome remains in the built-in
adapter until a host proves it needs a geometry contract.

The todo checkbox is a control hit, not gutter chrome. AppKit must resolve its exact hit
first and send the per-block toggle action through Session; that hit neither changes the
selection nor begins a block drag. Only a non-control gutter hit reaches the structural
selection/drag path. This priority is part of the P2 production-path regression contract.

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
- Checkbox-hit tests must prove that a control click dispatches only its target block's todo
  action and that an adjacent gutter drag still follows the structural path.
- Accessibility and clipboard selected text must use the same canonical fragment resolver
  as mutation, including empty logical blocks and direction-independent normalization.

## Clipboard Contract

Text selection and block selection need different structured payloads:

| Selection | Structured payload | Plain-text projection |
| --- | --- | --- |
| `T1/TN` | Partial endpoint fragments, complete intermediate fragments, source kind/parent information, relative hierarchy, and rebased inline marks | Kind-aware DFS line projection; an empty logical block remains an empty line (`a\n\nb`), while hierarchy stays in the structured payload |
| `B` | Deduplicated selected roots and each complete subtree in canonical DFS order | Kind-aware DFS line projection; empty blocks remain empty lines and relative hierarchy stays in the structured payload |

Notion used a partial multi-text payload for `TN` and a different whole-block payload for
`B`. SlopadEditor follows its open-edge merge behavior while retaining its own canonical model:

- A structured `B` payload pasted at a block boundary inserts complete copied blocks.
- The same payload pasted inside destination text absorbs the first copied block into the
  destination prefix and the last into the destination suffix. Their wrapper kinds are
  discarded; complete blocks strictly between them retain their kinds and subtrees.
- A `T1/TN` payload always behaves as a text slice. Partial first/last fragments merge into
  the destination edges and lose their source wrapper kinds. Complete intermediate blocks
  and atomic blocks retain their structure. Even a fully covered endpoint keeps text-slice
  behavior when the source mode was text selection.
- A structured paste mints fresh `BlockID`s and preserves only relative hierarchy.

Copy writes the versioned SlopadEditor structured representation and an ordinary plain-text
fallback. Paste chooses a valid supported SlopadEditor representation first, then plain text.
Invalid, unsupported-version, or oversized structured data fails closed to plain text.
If encoding a structured copy exceeds the 8 MiB cap, Copy and Cut deliberately write only
the ordinary plain-text representation; Cut mutates only after that plain write succeeds.
External plain text is inserted literally and is never auto-decoded as Markdown; Markdown
conversion remains an explicit import operation.

Structured paste must remain an edge format negotiated by the adapter and applied through
one canonical Session/model transaction. It must not become a second document model.

## Implementation Closure

The old-policy sites were migrated under their existing owners:

| Area | Implemented behavior |
| --- | --- |
| [`EditorSession+TextPointerDragInput.swift`](../Sources/SlopadEditorEngine/Session/TextInteraction/EditorSession+TextPointerDragInput.swift) | Latches text mode, hit-tests the current block, and resolves an empty-origin drag from the nearest non-empty edge in its direction. |
| [`EditorSession+VerticalMovementInput.swift`](../Sources/SlopadEditorEngine/Session/Navigation/EditorSession+VerticalMovementInput.swift) | Extends text by one visual destination across block boundaries without converting to `B`. |
| [`EditorSession+ActiveTextSelection.swift`](../Sources/SlopadEditorEngine/Session/TextInteraction/EditorSession+ActiveTextSelection.swift) | Keeps one focus-block native input descriptor while canonical `TN` retains both endpoints. |
| [`EditorSession+Rendering.swift`](../Sources/SlopadEditorEngine/Session/EditorSession+Rendering.swift) | Projects visible block-local text ranges and atomic block tint from prepared visible-order ranks. |
| [`EditorSession+RenderDamage.swift`](../Sources/SlopadEditorEngine/Session/EditorSession+RenderDamage.swift) | Computes selection damage only from visible ranks; it no longer materializes the full `TN` span per pointer update. |
| [`EditorSession+ClipboardWritePlan.swift`](../Sources/SlopadEditorEngine/Session/Selection/EditorSession+ClipboardWritePlan.swift) | Produces versioned text-slice or block-subtree payloads and a kind-aware plain fallback. |
| [`EditorSession+CommandInput.swift`](../Sources/SlopadEditorEngine/Session/InputRouting/EditorSession+CommandInput.swift) | Routes `TN` typing, deletion, Enter, formatting, indentation, Escape, Cmd-A, and structured paste through shared model semantics. |
| [`EditorModel+TextContentCommands.swift`](../Sources/SlopadEditorDocumentModel/Command/EditorModel+TextContentCommands.swift) | Replaces normalized cross-block spans, preserves the earlier endpoint, promotes removed-endpoint descendants, and records one transaction. |
| [`EditorModel+StructuredPasteCommands.swift`](../Sources/SlopadEditorDocumentModel/Command/EditorModel+StructuredPasteCommands.swift) | Applies fresh-ID structured forests using root-aware open-edge merging while preserving endpoint and middle subtrees. |
| [`AppKitEditorViewController.swift`](../Sources/SlopadEditorAppKitUI/AppKitEditorViewController.swift) | Classifies the origin once, keeps text/block drag modes distinct, and continues text selection during autoscroll. |
| [`AppKitActiveInputController.swift`](../Sources/SlopadEditorAppKitUI/AppKitActiveInputController.swift) | Negotiates typed plus plain clipboard representations, fail-closed paste fallback, and cut-after-write-success. |
| Session/AppKit tests and UI benchmark | Cover forward/reverse `TN`, empty and atomic blocks, native text/gutter event paths, autoscroll, structured clipboard, direct callback-contract composition, exact undo, and 100/1,000/10,000-block projection. They do not prove installed-IME delivery or the unimplemented live IME policy. |

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
| `D5` | Clipboard uses typed SlopadEditor text-slice/block-subtree payloads plus plain text, with the Notion-style open-edge rules above and no automatic Markdown decode. |
| `D6` | Undo/redo restores exact selection mode, anchor/focus direction, offsets, and affinity. |
| `D7` | `B` Shift-Right enters first-character `T1`, Shift-Left is a no-op; `TN` indent/outdent acts on every touched block; atomic and collapsed subtree content participates logically and uses block tint when it has no text geometry. |

### Implemented non-IME result — 2026-08-10

- D1–D7 are implemented for non-IME editing in `EditorModel`/`EditorSession`; the AppKit
  adapter owns only physical hit classification, native callbacks, pasteboard negotiation,
  drawing, and autoscroll. Direct composition callbacks retain the earlier overlay
  implementation; the live cross-block IME replacement policy is not implemented.
- `TN` remains two `TextPosition` endpoints. Visible selection and redraw damage use only
  prepared visible-order ranks; the 10,000-block regression tests assert viewport-bounded
  projection.
- Clipboard copy writes `com.hot666666.slopad.clipboard.v1` and `.string`. Structured
  paste validates version/shape/size at the edge, mints fresh IDs, preserves relative
  subtrees and marks, and applies one model transaction.
- [#72](https://github.com/hot666666/SlopadEditor/issues/72) isolated the signal 11 to test-fixture
  ownership: AppKit's `isReleasedWhenClosed` default conflicted with Swift ARC ownership.
  With test windows using ARC-only ownership, the fixed minimal regression passed locally
  in 20/20 fresh processes and the combined 656-test suite passed in 5/5 fresh processes.
  The deterministic UI benchmark covers forward/reverse text selection at 100, 1,000, and
  10,000 blocks with empty blocks mixed in.
- Installed input-method events currently do not reach the composition consumer in
  `SlopadDebugApp`. Repairing and proving **Apple built-in Korean 2-set** delivery is future
  work in [#71](https://github.com/hot666666/SlopadEditor/issues/71), followed by implementation
  and product verification of the decided live replacement policy. The
  [#76 native composition termination table](https://github.com/hot666666/SlopadEditor/issues/76)
  is its required callback-by-callback criterion; both issues remain open. #72's bounded
  local test stability is not installed-IME, native product input, visual, or device proof.
- The production `SlopadDebugApp` state harness passes all 18 scenarios, including the
  real cross-block text drag and viewport-derived down/up reveal boundaries.
- Caret review disposition: no change. Direct product use confirmed that AppKit's native
  automatic insertion indicator already has the intended idle and ordinary-input cadence.
  The currently unreachable installed-IME composition path is not a reason to add
  speculative composition-specific caret suppression; validate it after native delivery
  and composition semantics are implemented.
- Collapsed subtrees remain a P4 feature because SlopadEditor has no collapse state yet. D7 is
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

> **Status: completed gate record for the non-IME policy.** These gates were the exit
> criteria for the work recorded in [Implementation Closure](#implementation-closure).
> They are evidence of how that change was verified, not a standing work order. Gate 4's
> installed-IME items and the ADR 0014 live-replacement row remain open; everything else
> was met. For the current verification gates on new work, use [Testing](TESTING.md).

Evidence is accumulated by owner and by the real producer-to-consumer path. A lower-layer
test cannot substitute for a native callback, visual, or performance claim.

### Gate 0 — policy artifacts before executable work

- ADR 0014, this policy, the HTML map, and ROADMAP must contain the same D1–D7 outcomes.
- No product cell may remain marked `Decision needed`, `D1`…`D7`, or `unresolved`.
- Validate relative links, unique matrix row IDs, HTML controls, script syntax, and narrow
  responsive rendering. Record visual inspection separately from source checks.

### Gate 1 — canonical owner and transactions

The EditorModel-owned suites in `Tests/SlopadEditorEngineTests/EditorModel` must cover forward
and reverse `TN` for replacement, Backspace/Delete, Enter, Shift-Enter, formatting,
indent/outdent, and undo/redo. There is no separate `SlopadEditorDocumentModelTests` target;
`SlopadEditorDocumentModel` is exercised through the `SlopadEditorEngineTests` target, which declares it
as a direct dependency. Assertions must include:

- exact document DFS post-image, surviving `BlockID`/kind/parent, and fresh pasted IDs;
- promotion of removed endpoint children to the removed endpoint's parent;
- one transaction and one undo step per action;
- exact restored selection mode, anchor/focus direction, offsets, and affinity;
- empty endpoints/intermediate blocks, nested parents, atomic blocks, and all-content delete.

### Gate 2 — Session semantics and bounded projection

Focused `SlopadEditorEngineTests` must exercise every implemented matrix row through
`EditorSession.handleInput`, including pointer-origin latching, separator-only keyboard
steps, Escape, staged Cmd-A, `B` printable no-op, `B` Enter/Shift-Enter, and typed clipboard
payload routing. A direct `B` composition-event no-op remains callback-contract coverage,
not installed-IME delivery or implementation of the future live-replacement row. Rendering
tests must prove that `TN` stores only endpoints and projects only visible block-local
ranges while command-time operations still visit the complete logical span.

### Gate 3 — AppKit adapter and pasteboard negotiation

Focused `SlopadEditorAppKitUITests` must enter through the production adapter and assert:

- text-lane drag remains `T1/TN`; structural-margin drag remains `B`;
- focus-block native selection synchronization does not collapse canonical `TN`;
- copy writes both the versioned SlopadEditor type and `.string`;
- paste prefers a valid supported SlopadEditor payload, falls back on invalid/newer/oversized
  data, and never auto-decodes plain Markdown-looking text;
- a failed required pasteboard write prevents Cut deletion;
- the focused `C` uses AppKit's native automatic insertion-indicator cadence and
  selection/unfocused states hide it. Ordinary-input behavior is accepted from direct
  product use; composition-specific behavior remains future work after installed-IME
  delivery reaches the consumer rather than a speculative adapter rule.

### Gate 4 — native callback and visual behavior

Build and run `SlopadDebugApp`. The native callback smoke must use synthesized `NSEvent`
delivery through `NSWindow.sendEvent(_:)` and real `NSTextInputClient` callbacks rather
than calling semantic handlers directly. Manually inspect forward/reverse cross-block
drag, empty gaps, autoscroll, Escape/Cmd-A, clipboard round trips, caret blink, and Korean
composition/cancel with Apple's built-in Korean 2-set after installed-IME delivery is
repaired. Only then implement and verify [#76's native callback termination table](https://github.com/hot666666/SlopadEditor/issues/76),
including the committed-snapshot rule during live composition. The direct marked-text smoke
proves callback handling only; it is not evidence that an installed input method reaches
that consumer, nor that the decided live replacement policy is implemented.

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
swift build --product SlopadEditorAppKit --quiet
swift build --product SlopadEditorAppKitTextKit --quiet
swift build --product SlopadEditorAppKitUI --quiet
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
4. Route delete, paste, Enter, formatting, Escape, and Cmd-A through the shared range
   semantics. Composition remains open until Apple's built-in Korean 2-set delivery reaches
   the consumer; then implement [#76's decided live replacement lifecycle](https://github.com/hot666666/SlopadEditor/issues/76)
   against that real path, including the committed-snapshot boundary. Shared command
   availability/mixed-state derivation stays P2 until the built-in toolbar becomes its first
   real consumer.
5. Add clipboard-plan negotiation and kind-aware plain/structured serialization.
6. Add the built-in AppKit floating toolbar and per-block todo checkbox only against the
   shared Session snapshot/action contracts, with checkbox hit-control priority ahead of
   gutter drag; add a public host projection only when its first real consumer passes ADR
   0012.
7. Prove the real AppKit path in `SlopadDebugApp`, then run the 100/1,000/10,000-block UI
   benchmark gates before claiming completion.
