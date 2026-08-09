# 0014 - Latch Selection Mode at Gesture Origin and Support Cross-Block Text

Date: 2026-08-09

## Status

Accepted

Implementation: completed 2026-08-10

Validation boundary: owner and native-callback suites plus the deterministic 100/1,000/
10,000-block benchmark are complete. Installed-IME candidate-window and final manual
visual inspection remain separate product evidence.

## Context

Before this decision, Slopad started a body drag as text selection, constrained its endpoint to the
anchor block, and could convert the gesture to block selection after a vertical threshold.
That makes one continuous gesture change semantic meaning after it has begun. It also
prevents an ordinary character selection from ending at an exact text offset in another
block.

The canonical vocabulary already permits cross-block `TextSelection` endpoints, and ADR
0011 already projects such a selection into canonical DFS-order fragments for reviewed
editing. The missing decision is therefore not a global document-string coordinate. It is
which pointer gesture creates text selection, which creates structural block selection,
and how both modes remain distinct across input, rendering, clipboard, and mutation.

A direct Notion Playground survey on 2026-08-09 confirmed the intended distinction:
character-origin drags remain character selections across block boundaries, while
structural-margin drags select blocks. Empty blocks produce no character highlight but are
still part of the crossed structural span. The exact observations, settled product choices,
and verification boundaries are recorded in
[Selection Interaction Policy](../docs/SELECTION_INTERACTION_POLICY.md).

## Decision

### Pointer origin latches the selection mode

The pointer-down hit classification chooses the gesture mode for its complete lifetime:

- A text-lane origin begins text selection with a canonical `TextPosition` anchor.
- A gutter or structural-margin origin begins block selection with a `BlockID` anchor.
- Moving into another region never converts one mode into the other. Mouse-up closes only
  the runtime gesture; it leaves the resulting canonical selection in place.
- Autoscroll, viewport changes, and crossing empty blocks preserve the latched mode.

The AppKit adapter classifies platform geometry and sends a typed begin event. Session owns
the latched gesture runtime and semantic transition. `SlopadBlockLayout` and the text
backend answer block and block-local text hit-test facts; neither owns the selection.

### Cross-block text uses two canonical endpoints

`TextSelection(anchor:focus:)` remains the canonical representation. Each endpoint is a
`TextPosition(blockID:offset:affinity:)`; selection direction is preserved. Canonical DFS
order is used only to normalize the affected span for a command or projection. Slopad does
not introduce a flattened document string or a global integer position space.

Crossing a block boundary is a logical separator step. It can produce a non-collapsed
cross-block selection with no selected glyph in either endpoint block, such as
`A.end → B.start`. Empty intermediate blocks likewise have no text selection rectangle.
They remain in the logical touched span for Escape, structured clipboard, deletion, and
other structural consequences.

### Rendering is a visible projection

Session derives block-local selected ranges only for visible blocks. The text backend
continues to resolve and draw geometry for one block-local range at a time. AppKit paints
those rectangles and keeps only the focus block synchronized with the singular native text
input client.

The canonical selection stays O(1) in span length. Ordinary render and pointer updates
must not materialize every block between the endpoints; command-time operations such as
copy or delete may traverse the affected canonical span. The implementation must add a
measured 10,000-block drag/scroll gate before this decision is considered shipped.

### Text editing acts on the range, independent of input language

Typing, committed text, paste, Backspace, Delete, cut, and inline formatting apply to the
selected text fragments whether the range is within one block or crosses blocks. A
cross-block replacement is one canonical transaction and one undo step. Forward and
reverse selections have the same document result.

IME is not a separate product policy. Marked-text begin/update/commit/cancel uses the same
replacement semantics through the native composition lifecycle. Each callback updates the
actual editing content; Session groups those updates as one composition/history session
and advances the externally committed revision only at commit. Marked-range geometry and
candidate-window presentation remain runtime state. Cancellation follows the AppKit
callback result instead of maintaining a shadow document solely for rollback.

### Block selection remains an explicit structural mode

Block selection is created only by a structural pointer origin or an explicit keyboard
transition such as Escape or the final Cmd-A escalation. It continues to carry structural
roots/order and enables whole-block clipboard, deletion, navigation, indentation, and
reorder behavior. A text-origin gesture never becomes block selection merely because it
crosses a block boundary.

### High-level UI consumes projections, not selection policy

Toolbar, context-menu, inspector, clipboard, accessibility, and future UIKit surfaces do
not switch over `EditorSelection` to decide what commands mean. Session derives a
viewport-independent command state and a separate viewport-dependent selection
presentation from the canonical selection. UI sends the same typed semantic actions as
native input; the model revalidates and applies them through the same command path.

Search, comments, AI highlights, and remote cursors are derived decorations rather than
additional local canonical selections. Asynchronous range UI uses an opaque stale-source
check instead of locking selection or applying to whatever range happens to be active
later. Concrete types remain internal/package until a real host consumer justifies public
exposure.

## Consequences

- The threshold conversion from text drag to block selection was removed.
- Text navigation preserves the anchor and moves the focus one native navigation step
  across block boundaries instead of converting Shift-Up/Down to block selection.
- Snapshot/render contracts now carry a viewport-bounded collection of block-local text
  selection fragments in addition to the singular active input descriptor.
- High-level UI still needs shared command availability/mixed-value facts; selection
  geometry facts are Session-owned and implemented. The remaining command-state projection
  belongs to P2 and must not move policy into UI.
  it must not duplicate command predicates or toolbar placement inside the model.
- Clipboard and editing commands share one canonical selected-fragment traversal;
  render-time code must not reuse that full-span traversal.
- Escape converts a caret or text selection into the block selection covering every
  logically touched block; a subsequent Escape clears block selection.
- Cmd-A first expands text at its current scope, then escalates to whole-document block
  selection. Empty-block and cross-block details are normative in the policy document.
- Source and tests implement the decision. The policy document records the closed migration
  sites, focused evidence, benchmark scales, and remaining manual verification boundary.

The implementation details that were initially left as gates are now settled in the
normative policy: removed-endpoint children are promoted to the removed endpoint's parent;
an all-block deletion retains one empty paragraph; printable and IME input are ignored in
block selection; cross-block Enter/Shift-Enter use delete-then-existing-command semantics;
clipboard uses versioned Slopad text-slice/block-subtree payloads plus literal plain text;
history restores exact selection direction and affinity; and atomic or collapsed content
participates logically with block tint where text geometry does not exist.
