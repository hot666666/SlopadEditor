# 0006 - Source Layout Exposes Ownership

Date: 2026-07-08

## Status

Accepted

## Context

Slopad has several layers that intentionally expose a small interface to other callers:
public host-facing surface, package-only owner interfaces between SwiftPM targets, and
target-internal implementation details.

If all files are arranged only by broad technical categories or folder symmetry, a reader
cannot tell which type is the interface, which target owns the behavior, and which files
are implementation details. This also makes cleanup risky because helpers can look like
new modules even when they are only one owner's local policy.

The source tree should help developers understand the architecture before opening every
file.

## Decision

Arrange source files so externally consumed surface is easy to find, and implementation
details sit under owner/read-intent folders.

Rules:

- Public host-facing facade and output values stay visible near the target root.
- Package interfaces used by another target stay visible near the owner target root,
  usually as owner-named files such as `EditorModel+...` or `BlockLayout+...`.
- Target-internal implementation files are grouped by the reason a maintainer would read
  them: command handling, history, invalidation, layout pass, geometry, visible order,
  text layout, height index, rendering, input routing, and similar owner-specific intent.
- Folder names describe ownership and read intent. They do not create independent layers
  by themselves.
- Do not create generic folders such as `Helpers`, `Managers`, `Services`, `Policies`, or
  broad `Input`/`Output` buckets unless the producer, consumer, invariant, and second use
  case prove a real module boundary.

Target-specific placement:

- `Sources/SlopadEngine/Session`
  - Root: `EditorSession`, public snapshot/update/render output values, and thin public
    facade entrypoints.
- `Sources/SlopadEditorModel`
  - Root: `EditorModel`, package entrypoints consumed by Session, and cross-target
    semantic change facts.
- `Sources/SlopadBlockLayout`
  - Root: `BlockLayout`, package entrypoints consumed by Session, and package geometry or
    invalidation outputs when another target needs them.
- `Sources/SlopadCoreModel`
  - Folders hold public vocabulary and backend seam values by domain: document, text,
    selection, composition, interaction, geometry, and layout.
- `Sources/SlopadDataStructure`
  - Pure data structures only. No editor, block, layout, or platform vocabulary.
- `Sources/SlopadAppKitTextKit`
  - TextKit2 backend implementation and interop only.
- `Sources/SlopadAppKitUI`
  - Public controller, style consumption, and chrome contract remain easy to identify.
    Native input routing, fragment/feedback drawing, active input, drag autoscroll, and
    surface synchronization helpers remain target-internal unless a real cross-target
    development consumer proves package access is required.

## Consequences

- A developer can scan directories and follow the owner chain from the platform adapter
  through `Session -> EditorModel / BlockLayout`, then into owner-local
  `TextLayout / HeightIndex -> DataStructure` implementation.
- Moving a file is valid only when the owner/read-intent changes or the current placement
  hides the real interface.
- A helper that is consumed by one owner stays local to that owner instead of being
  promoted into shared vocabulary.
- Public/package surface changes should be reviewed together with file placement. If a
  type is exposed externally, the file location should make that exposure obvious.
- Tests mirror source ownership by import and responsibility, not by mechanical folder
  symmetry.
