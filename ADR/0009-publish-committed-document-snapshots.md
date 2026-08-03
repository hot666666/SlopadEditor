# 0009 - Publish Committed Full-Document Snapshots On Demand

Date: 2026-07-18

## Status

Accepted

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

Content edits, insertions, deletions, reorders, parent changes, undo, redo, and explicit or
implicit IME commit advance the revision. Selection, layout, render, scrolling, compatible
selection inside live composition, composition begin/update, and composition cancel do
not. `resetDocument` establishes a new Session baseline at revision zero and is not a user
commit.

The full snapshot never contains viewport, selection, scroll, layout, or live composition
state. It is a `Sendable` value; the mutable `EditorSession` remains confined to one
executor.

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
