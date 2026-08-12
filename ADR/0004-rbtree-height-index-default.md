# 0004 - Use RBTree-Backed Block Height Indexing by Default

Date: 2026-07-08

## Status

Accepted

## Context

Block editors need fast y-position and prefix-sum queries, but they also perform middle
range structural edits: block insertion, deletion, subtree deletion, subtree movement,
indent/outdent, and height updates from text edits.

An array-backed height index is attractive for full rebuild and read-heavy paths, but
middle-range structural mutation can make index-map rewrites expensive at larger document
sizes.

Benchmarks on 2026-07-06 compared the default RBTree-backed storage with an experimental
array-backed storage at 100, 1000, and 10000 blocks. The array version won some
read/rebuild-heavy paths. RBTree stayed much stronger on subtree delete/reorder pressure,
especially at 10000 blocks.

## Decision

Keep `RBTreeBlockHeightIndexStorage` as the default implementation behind
`BlockHeightIndexStorage`.

Keep the array storage only as a private experimental compile-time implementation. Do not
expose storage selection through `EditorSession`, `SlopadEditorCoreModel`, or public host API.

## Consequences

- `PrefixSumRedBlackTree` remains a pure data structure in `SlopadEditorDataStructure`.
- The y/height domain stays owned by `BlockHeightIndexStorage`.
- Storage comparisons should use both session-level structural benchmarks and AppKit UI
  benchmarks. AppKit FPS alone is not enough to choose the storage default.
- A future hybrid storage design must preserve the same owner surface and prove subtree
  mutation behavior against the existing baselines.
