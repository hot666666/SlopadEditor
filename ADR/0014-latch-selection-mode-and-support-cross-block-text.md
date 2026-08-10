# 0014 - Latch Selection Mode at Gesture Origin and Support Cross-Block Text

Date: 2026-08-09

## Status

Accepted

Implementation: the non-IME selection, editing, clipboard, and rendering policy was
completed 2026-08-10. The live cross-block IME replacement policy is not implemented or
product-verified.

Validation boundary: owner suites, direct native-callback contract tests, and the
deterministic 100/1,000/10,000-block benchmark cover the implemented non-IME behavior.
Direct `setMarkedText` calls prove how the existing callback consumer handles an overlay;
they do not prove delivery from an installed input method. In current product use,
installed-IME input does not reach the composition consumer, so routing, candidate-window
behavior, and the decided live replacement policy remain future product work.

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

IME is not a separate product policy. The decided future target is for marked-text
begin/update/commit/cancel to use the same replacement semantics through the native
composition lifecycle: each callback would update the actual editing content, Session
would group those updates as one composition/history session, and the externally committed
revision would advance only at commit. Marked-range geometry and candidate-window
presentation would remain runtime state, and cancellation would follow the AppKit callback
result instead of maintaining a shadow document solely for rollback.

That future live group may update transaction-local canonical editing content, but it must
not expose provisional marked text through the public persistence surface.
`documentSnapshot` remains the last published committed document and revision until close
atomically publishes a changed document; autosave during composition therefore stores that
prior snapshot, while an explicit save first flushes composition. The exact native callback
termination table—first/subsequent `setMarkedText`, `insertText`, `unmarkText`, Escape,
undo/redo, synchronized commands, focus loss, and explicit flush—is the implementation
criterion in [#76](https://github.com/hot666666/Slopad/issues/76). It is implemented only
after real installed-IME delivery, including Apple's built-in Korean 2-set, is proven in
the product path.

That future target is not the current implementation. Today Session keeps an effective-
document composition overlay while composing and mutates canonical content once at commit.
Installed-IME events do not currently reach this consumer in product use; direct
`setMarkedText` tests exercise the callback contract only.

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

The first P2 product consumer is a built-in AppKit floating toolbar plus todo checkbox.
`EditorSession` owns availability/mixed state and the exact per-block todo action; AppKit
owns placement and hit classification. A checkbox control hit dispatches that action before
gutter selection or block drag is considered, so the adapter never infers a todo mutation
from selection geometry.

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
- Source and tests implement the non-IME decision. The policy document records the closed
  non-IME migration sites, focused evidence, benchmark scales, and the unimplemented IME
  delivery/replacement boundary.

The details that were initially left as gates are now settled in the normative policy:
removed-endpoint children are promoted to the removed endpoint's parent; an all-block
deletion retains one empty paragraph; printable input is ignored in block selection and
future installed-IME input follows the same target; cross-block Enter/Shift-Enter use
delete-then-existing-command semantics;
clipboard uses versioned Slopad text-slice/block-subtree payloads plus literal plain text;
history restores exact selection direction and affinity; and atomic or collapsed content
participates logically with block tint where text geometry does not exist.
