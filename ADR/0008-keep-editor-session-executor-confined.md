# 0008 - Keep EditorSession Confined to One Executor

Date: 2026-07-17

## Status

Accepted

## Context

`EditorSession` owns mutable editor, layout, composition, and interaction runtime state.
Its public methods are synchronous so native adapters can translate one platform callback,
apply the resulting engine transition, and synchronize their surface as one serialized
operation.

The type previously declared `@unchecked Sendable` without protecting those mutable values.
The AppKit adapter happened to call it from `MainActor`, but the declaration incorrectly
allowed another host to transfer one Session between executors and call it concurrently.

## Decision

`EditorSession` is not `Sendable`. The executor that creates a Session owns it for its
entire lifetime and calls it serially.

Hosts may transfer `Sendable` input values, `EditorUpdate` values, and
`EditorSessionSnapshot` projections across isolation boundaries. A host that needs an
actor-owned editor keeps the Session inside that actor instead of transferring the mutable
Session itself.

For persistence, the host reads the committed `EditorDocumentSnapshot` on that same owner
executor, then may transfer its immutable `blocks` to another executor for the synchronous
pure codec defined by
[ADR 0015](0015-version-native-archive-and-keep-storage-host-owned.md). Epoch/revision may
guard against a stale in-process encode, but neither token nor the Session crosses into the
archive or becomes a storage revision.

The headless engine is not globally `MainActor`-isolated. Platform adapters choose their
own executor; the default AppKit adapter uses `MainActor`.

## Consequences

- The compiler no longer accepts an unsupported cross-executor transfer merely because of
  an unchecked conformance.
- Session calls remain synchronous and add no locking or actor-hop overhead.
- AppKit's synchronized public actions continue to run on `MainActor`.
- A future platform adapter must choose one executor for each Session and keep all Session
  calls serialized there.
- Snapshot and update values remain the cross-isolation read/projection boundary.
- Off-owner archive encoding starts only after the host captures the immutable committed
  blocks on the Session owner executor; storage I/O remains outside Session.
