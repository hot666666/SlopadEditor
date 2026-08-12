# ROADMAP

This document contains only unfinished product direction, priority, and exit criteria.
Current source and tests define what SlopadEditor does today. [Architecture](ARCHITECTURE.md),
the [architecture map](slopad-architecture-map.html), and the ADRs define established
boundaries; the active tracking issue defines the executable work order.

When source and this document disagree about intent, fix the document or open an issue
before changing code. Historical handoffs and completion pages are evidence, not work
orders.

## Current Baseline

[Epic #23](https://github.com/hot666666/SlopadEditor/issues/23) is complete. Its
[completion page](epic-23-status.html) records historical integration evidence. The
implemented baseline includes the headless Session/model/layout split, the curated AppKit
and SwiftUI host surfaces, coherent TextKit2 capabilities and bounded prepared-layout
reuse, inline marks and parser-free typed shortcuts, slash-only block commands, committed
document snapshots, reviewable atomic document patches, and fail-closed Markdown
decode/encode. The opt-in native archive also preserves canonical identities through a
strict fail-closed V1 codec while keeping storage lifecycle host-owned. ADR 0014's non-IME
cross-block text selection is implemented with
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
- Markdown typed-input rules and whole-document conversion remain separate. The two closed
  whole-document codecs do not justify a format plugin registry.
- Text backend cache identity follows the effective measurement request and style, not a
  model revision convention.
- Caret/selection geometry is published through Session facts; AppKit UI does not bypass
  Session to ask the backend for editing meaning.
- Markdown is not persistence state. Its semantic round-trip creates fresh `BlockID`s;
  [ADR 0015](../ADR/0015-version-native-archive-and-keep-storage-host-owned.md)'s native
  archive preserves canonical block identity instead. Markdown remains an explicit
  whole-document import/export format, not a reload format. Archive storage timing,
  atomicity, conflict handling, retry, and recovery remain host-owned.
- ADR 0012's ordinary-host contract is continuously gated by
  `bash scripts/verify-host-surface.sh`. It runs the one-product AppKit and SwiftUI public
  lifecycle fixtures on every pull request; format-consumer fixtures remain separate.

## Priorities

These are capability buckets, not permission to implement without an owner decision and a
bounded tracking issue.

### P0 — Preserve the continuous ADR 0012 host-surface gate

[#69](https://github.com/hot666666/SlopadEditor/issues/69) implemented the always-run Epic #67
baseline. [`scripts/verify-host-surface.sh`](../scripts/verify-host-surface.sh) is now the
canonical gate for both ordinary AppKit and SwiftUI lifecycle fixtures, and CI invokes it
on every pull request. This is an ongoing boundary constraint, not a feature waiting for
completion.

- Keep `SlopadEditorAppKit` as the ordinary one-product/one-import path and `SlopadEditorSwiftUI` as
  the declarative lifecycle surface.
- Admit new host operations only as synchronized actions, style/chrome customization,
  engine input contracts, or a complete custom-adapter requirement.
- Keep both downstream host fixtures exercising mount → edit → observe → flush → replace
  → unmount without `@testable`, package access, or underlying-module bypass.
- Keep those ordinary one-product lifecycle fixtures separate from opt-in format-consumer
  fixtures. Markdown and the native archive codec each prove their own format boundary;
  neither substitutes for the AppKit or SwiftUI lifecycle gate.

Exit: an ordinary host can integrate, persist, focus, resize, and customize supported
chrome without touching raw callbacks, viewport ownership, TextKit graphs, model/layout
internals, or development hooks.

### P1 — Close cross-block selection product evidence

- Exercise forward/reverse text and structural drags, empty-origin drag, autoscroll,
  Escape/Cmd-A, structured clipboard round trips, and caret/selection chrome manually in
  `SlopadDebugApp`.
- Make **Apple's built-in Korean 2-set** installed-IME delivery reproducible through the
  opt-in DebugApp native-input trace. One 2026-08-10 diagnostic session observed a real
  marked update reach the composition consumer; it did not prove commit/cancel lifecycle,
  candidate-window behavior, or repeatability. Direct `setMarkedText` tests prove only the
  consumer's callback contract, not installed-input-method delivery.
- Only after that real UI evidence exists, implement ADR 0014's decided live cross-block
  replacement through [#76](https://github.com/hot666666/SlopadEditor/issues/76)'s native
  callback close table: grouped history, exact cancel/redo restoration, candidate-window
  behavior, and the one committed-revision rule. Do not infer product behavior from direct
  callback injection.
- During that future live composition, transaction-local editing content may change, but
  public `documentSnapshot` remains the last published committed document and revision
  until close publishes a changed document. Autosave therefore persists the prior snapshot;
  an explicit save first commits composition.
Exit: the implemented non-IME D1–D7 behavior has recorded manual visual evidence, Apple's
built-in Korean 2-set delivery reaches the consumer, the decided live replacement lifecycle
is implemented and product-verified, and the canonical repository-wide test entrypoint exits
successfully in one process.

### P2 — Complete product command reachability

- Make the first product chrome a built-in AppKit floating toolbar and todo checkbox. It
  must not move mutation semantics out of `EditorModel`/`EditorSession`.
- `EditorSession` owns command availability and mixed state; the AppKit toolbar consumes
  that projection and sends typed actions back through the same Session/model path. It must
  not switch over `EditorSelection` or inspect TextKit directly.
- A todo checkbox is an exact per-block Session action, not an inferred selection action.
  AppKit first resolves the checkbox hit control; that hit dispatches the todo action and
  never starts gutter selection or a block drag. Only non-control gutter hits use the
  structural selection/drag path.
- Give asynchronous link/comment/AI surfaces an opaque stale-selection source only when a
  concrete feature needs it; synchronous toolbar actions keep using the current selection.
- Decide whether generalized suggestions need a public policy contract or remain separate
  adapter UI; the current slash runtime stays non-canonical.
- Keep command selection and presentation distinct from command definition/application.

Exit: the built-in floating toolbar and per-block todo checkbox reach supported commands
through Session, with one transaction/undo per command, exact checkbox-versus-gutter hit
priority, and no public model internals.

### P3 — Add explicit import/export UX

- Build caller-owned Markdown import/export UX and failure handling on top of the existing
  fail-closed codec; it handles whole documents only and never becomes an implicit
  persistence or paste path.
- The embedding app owns files, databases, cloud sync, autosave, conflict resolution,
  retry, and error UX. `SlopadEditorArchive` owns neither storage nor lifecycle policy.
- Add GFM table support only after the Core table vocabulary in
  [#50](https://github.com/hot666666/SlopadEditor/issues/50) has a real owner and invariants.

Exit: Markdown import/export behavior is explicit, diagnostics reach product UX, and the
host retains all native archive storage policy.

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
- Convenience APIs can pull semantics into `SlopadEditorAppKit`/`SlopadEditorAppKitUI`; apply the
  ADR 0012 host-surface test before widening them.
- A partial text-renderer hook would split measurement, geometry, and drawing. Full text
  replacement requires a coherent adapter/backend pair.
- Structured paste, collapsed state, or using Markdown as persistence can each
  accidentally become a second canonical model if ownership is not decided first.
- Full-rebuild layout remains the correctness baseline; large documents still require
  measured incremental and viewport-driven strategies.
- Snapshot undo/redo is simple and correct but may need a measured memory strategy for
  large documents.
