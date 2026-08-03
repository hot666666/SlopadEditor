# Architecture Decision Records

This directory stores durable architecture decisions for Slopad. ADRs are for decisions
that should survive individual refactor slices: ownership, target graph, public surface,
platform seams, benchmark policy, and performance-critical storage choices.
See the current [architecture map and philosophy](../docs/ARCHITECTURE.md) before reading
the decisions that led to it.

## Records

- [0001 - Use a headless session facade for platform hosts](0001-headless-session-facade.md)
- [0002 - Keep the SwiftPM target graph as the architecture boundary](0002-swiftpm-target-graph.md)
- [0003 - Keep text layout behind a backend seam](0003-text-layout-backend-seam.md)
- [0004 - Use RBTree-backed block height indexing by default](0004-rbtree-height-index-default.md)
- [0005 - Keep benchmark APIs out of the public library surface](0005-benchmarks-as-development-targets.md)
- [0006 - Source layout exposes ownership](0006-source-layout-exposes-ownership.md)
- [0007 - Provide AppKit UI as a reusable adapter package](0007-appkit-ui-adapter-package.md)
- [0008 - Keep EditorSession confined to one executor](0008-keep-editor-session-executor-confined.md)
- [0009 - Publish committed full-document snapshots on demand](0009-publish-committed-document-snapshots.md)
- [0010 - Provide an AppKit platform facade](0010-appkit-platform-facade.md)
- [0011 - Provide reviewable atomic document transactions](0011-reviewable-atomic-document-transactions.md)
