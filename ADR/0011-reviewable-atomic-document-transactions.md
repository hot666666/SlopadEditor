# 0011 - Provide Reviewable Atomic Document Transactions

Date: 2026-07-23

## Status

Accepted

## Context

An assistant or another external coordinator needs enough canonical context to propose a
multi-operation edit, let the app review it, and apply the accepted result atomically.
Replaying insert/delete/reorder commands from outside would expose internal policy,
produce partial intermediate states, and make one reviewed proposal span multiple history
entries and update callbacks.

`EditorDocumentSnapshot` already exposes the complete canonical tree for persistence, but
it deliberately excludes selection and Session identity. Its revision does not change for
selection-only movement and resets to zero when an AppKit controller replaces its Session.
It therefore cannot safely authorize a later mutation. Live IME composition is also a
Session overlay rather than canonical content, so a context captured while marked text is
active would not describe one stable mutation base.

## Decision

Add sibling public APIs to `EditorSession` and `AppKitEditorViewController`:

- `documentContextSnapshot()` captures a complete canonical `EditorDocumentSnapshot`,
  exact `EditorSelection`, structured selected content, and an opaque
  `EditorDocumentSource`.
- `applyDocumentPatch(_:)` accepts that source, a complete canonical
  `replacementBlocks` post-image, and `selectionAfter`.

The source token captures a private per-Session epoch, committed document revision, and
exact selection. Apply compares all three. This rejects a document commit, selection-only
move, and reset ABA. The token is short-lived and non-persistent; it exposes no public
fields or initializer.

Query and apply both reject active Session composition with
`EditorDocumentTransactionError.activeComposition`. The AppKit sibling methods also
reject native marked text. A host that wants to continue calls
`commitActiveComposition()` and captures a fresh context.

Selected content is a canonical projection:

- A `TextSelection`, including cross-block endpoints, becomes canonical DFS-order
  fragments. Each fragment includes block ID, parent, kind, source range, sliced text, and
  fragment-relative rebased marks.
- A `BlockSelection` removes selected descendants already covered by an ancestor and
  returns canonical selected roots plus each complete subtree in DFS order.
- caret and inactive selections return no selected content while remaining part of the
  exact context and source.

Context and selected-content values are output-only Session projections. Their
initializers are not public. Selected-content values conform to `Encodable` for review
transport but not `Decodable`, so a host cannot decode unchecked projection combinations.
`EditorDocumentPatch` remains the public host-constructed input.

The patch is a full post-image rather than public operation objects. Before mutation,
`SlopadCoreModel` validates non-empty input, unique IDs, canonical `BlockContent` marks,
parent existence, absence of cycles, canonical parent-before-child DFS order, and
selection bounds. Public failures are typed errors, not preconditions. Parent-chain and
document invariant preorder validation use iterative stacks so an unbounded public
post-image cannot overflow the process stack. `EditorModel` installs a valid changed
post-image and selection as one snapshot-backed transaction. Session publishes one
committed revision and one update. One undo/redo step restores the whole before/after
state. An exact document-and-selection no-op returns `nil` without history, revision,
callback, layout, or render work.

`AppKitEditorViewController` only adds synchronized forwarding: after Session success it
publishes one `onUpdate`, then converges render, native text, selection, focus, and reveal
state. The `SlopadAppKit` facade explicitly aliases every public context/patch type so an
ordinary host retains the one-product, one-import contract.

## Consequences

- External proposals can express composite insert, delete, replace, and reorder results
  without widening public command or `EditorModel` access.
- Persistence keeps using `documentSnapshot`; review and mutation authorization use
  `documentContextSnapshot()`. The two APIs share the canonical document representation
  but not purpose or lifetime.
- Source validation is intentionally stricter than revision comparison. Hosts must
  re-query after cursor movement, document changes, reset, or composition commit.
- Full post-image projection and validation are O(document size). This is appropriate for
  reviewed assistant transactions, not ordinary per-keystroke input.
- Publicly mutable `BlockContent` is accepted only when its marks still equal canonical
  normalization for the current text; otherwise apply returns `invalidContent(blockID:)`
  without mutation.
- Session starts a fresh derived `BlockLayout` state after a changed post-image because
  public block values may retain IDs while replacing content and canonical visible order.
- `Fixtures/DownstreamAppKitHost` compile-runs the contract through `SlopadAppKit` alone;
  owner tests cover structured selection, CAS failures, validation rollback, no-op,
  history, callbacks, and surface synchronization.
