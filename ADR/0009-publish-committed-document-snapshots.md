# 0009 - Publish Committed Full-Document Snapshots On Demand

Date: 2026-07-18

## Status

Accepted

Amended 2026-08-10 by [ADR 0014](0014-latch-selection-mode-and-support-cross-block-text.md):
IME callbacks now update canonical editing content live while deferring the committed
revision until the composition history group closes.

## Context

Downstream document products need to persist the complete canonical block tree after an
editor mutation. `EditorSessionSnapshot.visibleBlocks` is a viewport projection and omits
offscreen content. The package `EditorChange` values are layout-invalidation facts; they do
not contain a complete public description of content, insertion position, deletion,
reordering, and parent changes.

The package `Document.revision` also cannot be the host persistence token. Undo restores an
older document snapshot, so a divergent edit can reuse the same internal revision for
different content. Copying every block into every typing update would instead make each
keystroke O(document size), even for hosts that debounce persistence.

## Decision

`SlopadEngine` publishes two related public values:

- `EditorDocumentRevision` is a monotonically increasing token scoped to one
  `EditorSession`.
- `EditorDocumentSnapshot` contains that revision and every canonical
  `EditorBlockInput` in depth-first preorder. Parent identity and array order preserve the
  complete tree and sibling order.

`EditorUpdate.committedDocumentRevision` is non-`nil` only when canonical content or
structure commits. A host reads `EditorSession.documentSnapshot` synchronously on the
Session-owning executor when it needs the full immutable projection. The AppKit adapter
exposes the same projection as `AppKitEditorViewController.documentSnapshot`; its
`onUpdate` callback runs synchronously, so a downstream host can read and verify the
matching snapshot before returning from the callback.

Content edits, insertions, deletions, reorders, parent changes, undo, and redo advance the
revision. Composition begin/update changes the current canonical blocks but remains inside
one open history group, so it does not advance the externally committed revision. Explicit
or implicit composition closure compares the final canonical document, selection, and
stored marks with the state before composition. A difference records one grouped history
item, and a document difference advances the committed revision once. Exact restoration of
all three closes only the runtime composition: it records no history, publishes no revision,
and leaves the existing redo branch intact. Cancellation follows the canonical
post-callback content reported by AppKit and uses the same comparison. Selection, layout,
render, scrolling, and compatible selection inside live composition do not by themselves
advance the revision.
`resetDocument` establishes a new Session baseline at revision zero and is not a user commit.

The full snapshot never contains viewport, selection, scroll, layout, marked-range, or
composition-lifecycle metadata. Its blocks are the current canonical editing content, so a
read during composition can contain live marked text while retaining the last committed
revision. Persistence hosts act on `committedDocumentRevision` or flush composition first;
they do not treat an arbitrary mid-composition read as a new committed snapshot. The value
is `Sendable`; the mutable `EditorSession` remains confined to one executor.

## Consequences

- A host can reconstruct the complete canonical document without `visibleBlocks`,
  `@testable`, or package access.
- Full-tree projection is O(document size), but occurs only when the host requests it.
  Debounced persistence can coalesce revision notifications before reading the latest
  snapshot.
- A revision is not a database revision and is not meaningful across Session reset. Hosts
  retain their own document identity and storage revision.
- A host that transfers update values to another executor must first obtain the matching
  snapshot on the Session owner executor. The engine does not retain historical snapshots
  for delayed revision lookup.
- Public-host fixtures and owner tests verify tree completeness, monotonic history changes,
  viewport independence, and the absence of persistence signals for runtime-only updates.
