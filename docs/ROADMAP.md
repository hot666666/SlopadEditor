# ROADMAP

This document contains only unfinished product direction, priority, and exit criteria.
Current source and tests define what Slopad does today. [Architecture](ARCHITECTURE.md),
the [architecture map](slopad-architecture-map.html), and the ADRs define established
boundaries; the active tracking issue defines the executable work order.

When source and this document disagree about intent, fix the document or open an issue
before changing code. Historical handoffs and completion pages are evidence, not work
orders.

## Current Baseline

[Epic #23](https://github.com/hot666666/Slopad/issues/23) is complete. Its
[completion page](epic-23-status.html) records historical integration evidence. The
implemented baseline includes the headless Session/model/layout split, the curated AppKit
and SwiftUI host surfaces, coherent TextKit2 capabilities and bounded prepared-layout
reuse, inline marks and parser-free typed shortcuts, slash-only block commands, committed
document snapshots, reviewable atomic document patches, and fail-closed Markdown
decode/encode. ADR 0014's non-IME cross-block text selection is implemented with
gesture-origin mode latching, viewport-bounded presentation/damage, D1–D7 editing
semantics, and a versioned structured clipboard plus literal plain-text fallback. Its
decided live cross-block IME replacement policy is not implemented or product-verified.

Do not reopen that work through a roadmap item. Verify exact current behavior in source
and tests, and use the architecture map to find the owning path.

## Settled Constraints

These constraints remain in force unless replaced by an ADR:

- Multi-block interaction has two distinct modes: cross-block `TextSelection` keeps two
  block-local endpoints, while `BlockSelection` represents structural selection. Pointer
  origin latches the mode; there is no global integer document position space. See
  [ADR 0014](../ADR/0014-latch-selection-mode-and-support-cross-block-text.md) and the
  [selection policy](SELECTION_INTERACTION_POLICY.md).
- `BlockKind` and inline mark vocabulary remain closed core enums until a concrete
  consumer proves an extension/preservation contract.
- Structure and content remain one canonical block store; do not add a second key-set
  invariant without measured need such as lazy content loading.
- Markdown typed-input rules and whole-document conversion remain separate. There is no
  format plugin registry while only one codec exists.
- Text backend cache identity follows the effective measurement request and style, not a
  model revision convention.
- Caret/selection geometry is published through Session facts; AppKit UI does not bypass
  Session to ask the backend for editing meaning.
- Markdown is not persistence state. Its semantic round-trip creates fresh `BlockID`s;
  persistence identity needs a separate decision.

## Priorities

These are capability buckets, not permission to implement without an owner decision and a
bounded tracking issue.

### P0 — Harden the host integration contract

- Keep `SlopadAppKit` as the ordinary one-product/one-import path and `SlopadSwiftUI` as
  the declarative lifecycle surface.
- Admit new host operations only as synchronized actions, style/chrome customization,
  engine input contracts, or a complete custom-adapter requirement.
- Keep both downstream host fixtures exercising mount → edit → observe → flush → replace
  → unmount without `@testable`, package access, or underlying-module bypass.

Exit: an ordinary host can integrate, persist, focus, resize, and customize supported
chrome without touching raw callbacks, viewport ownership, TextKit graphs, model/layout
internals, or development hooks.

### P1 — Close cross-block selection product evidence

- Exercise forward/reverse text and structural drags, empty-origin drag, autoscroll,
  Escape/Cmd-A, structured clipboard round trips, and caret/selection chrome manually in
  `SlopadDebugApp`.
- Repair installed Korean IME delivery so product events reach the existing composition
  consumer. Direct `setMarkedText` tests prove only that consumer's callback contract, not
  installed-input-method delivery.
- After delivery is proven, implement ADR 0014's decided live cross-block IME replacement,
  grouped history, commit/cancel, and candidate-window behavior against the real product
  path. Do not infer product behavior from direct callback injection.
- Resolve or isolate the Swift Testing helper's AppKit `NSWindow` teardown signal 11. A
  440-test focused Engine run and a 90-test focused AppKit run are recorded passing, but
  the AppKit target can still fail intermittently during teardown and the combined suite
  fails more often. Keep the passing owner runs as bounded evidence, not a stability
  claim, until the runner issue is closed.

Exit: the implemented non-IME D1–D7 behavior has recorded manual visual evidence, installed
IME delivery reaches the consumer, the decided live replacement lifecycle is implemented
and product-verified, and the canonical repository-wide test entrypoint exits successfully
in one process.

### P2 — Complete product command reachability

- Add toolbar reachability and todo checkbox product chrome without moving mutation
  semantics out of `EditorModel`/`EditorSession`.
- Drive enablement, mixed inline/block values, and selection geometry from the shared
  interaction projections defined by the selection policy; toolbar views must not switch
  over `EditorSelection` or inspect TextKit directly.
- Give asynchronous link/comment/AI surfaces an opaque stale-selection source only when a
  concrete feature needs it; synchronous toolbar actions keep using the current selection.
- Decide whether generalized suggestions need a public policy contract or remain separate
  adapter UI; the current slash runtime stays non-canonical.
- Keep command selection and presentation distinct from command definition/application.

Exit: product UI can reach supported block and inline commands through Session, with one
transaction/undo per command and no public model internals.

### P3 — Add import/export UX and choose persistence identity

- Build caller-owned Markdown import/export UX and failure handling on top of the existing
  fail-closed codec; do not add lossy fallback inside `SlopadMarkdown`.
- Decide in a persistence ADR whether storage uses a native archive, Markdown plus a
  sidecar, or accepts fresh identities on reload.
- Add GFM table support only after the Core table vocabulary in
  [#50](https://github.com/hot666666/Slopad/issues/50) has a real owner and invariants.

Exit: import/export behavior is explicit, diagnostics reach product UX, and persistence
identity/selection/reference consequences are documented and tested.

### P4 — Design collapsed subtrees

- Decide whether collapsed state is canonical document content, host preference, or
  Session runtime before implementation.
- Update visible order, selection, reveal, hit testing, render, clipboard, drag/drop, and
  benchmarks as one coherent feature.

Exit: collapsed content changes visibility and interaction without corrupting canonical
tree structure or creating two collapse owners.

### P5 — Close native text and performance gaps

- Resolve native soft-line beginning/end behavior; it currently falls back to logical
  block boundaries.
- Decide whether secondary bidi insertion location needs an additional platform-neutral
  transient fact beyond the current navigation context.
- Extend 100/1,000/10,000-scale gates for structured paste, collapsed reveal, and new
  product interactions. Add cache indices or history coalescing only after measurements
  show the need.

Exit: new UX paths have explicit correctness scenarios and measured thresholds, with
ordinary typing/composition remaining bounded around changed content.

### P6 — Expand platforms

- Design UIKit or another native adapter only after the AppKit contract is stable enough
  to serve as a reference.
- Preserve `EditorSession` semantics and the coherent text-layout capability seam rather
  than sharing platform objects.

Exit: the new adapter proves the same owner boundaries and native behavior through its own
platform-hosted tests and fixtures.

## Open Risks

- TextKit2 geometry varies with OS, font, and layout-manager behavior; unit tests should
  assert invariants and real UI paths should cover native interaction.
- Convenience APIs can pull semantics into `SlopadAppKit`/`SlopadAppKitUI`; apply the
  ADR 0012 host-surface test before widening them.
- A partial text-renderer hook would split measurement, geometry, and drawing. Full text
  replacement requires a coherent adapter/backend pair.
- Structured paste, collapsed state, or Markdown persistence can each accidentally become
  a second canonical model if ownership is not decided first.
- Full-rebuild layout remains the correctness baseline; large documents still require
  measured incremental and viewport-driven strategies.
- Snapshot undo/redo is simple and correct but may need a measured memory strategy for
  large documents.
