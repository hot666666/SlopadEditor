# 0015 - Version the Native Archive and Keep Storage Lifecycle Host-Owned

Date: 2026-08-10

## Status

Accepted

Decision tracking: [issue #75](https://github.com/hot666666/SlopadEditor/issues/75) owns this ADR
and its fixed contract. Implementation tracking:
[issue #78](https://github.com/hot666666/SlopadEditor/issues/78) owns the `SlopadEditorArchive`
product/target, codec, CoreModel validation seams, and downstream fixture.

## Context

ADR 0009 publishes the complete committed canonical tree as parent-before-child
`[EditorBlockInput]`. That projection solves when and where a host reads the document, but
it intentionally does not choose a durable representation. Persisting
`EditorSessionSnapshot.visibleBlocks` would lose offscreen blocks, while persisting
`EditorDocumentSnapshot` directly would incorrectly give process-local Session epoch and
revision a durable meaning.

Markdown cannot fill this role. ADR 0013 guarantees semantic import/export, not identity:
decoding Markdown creates fresh `BlockID`s and normalizes source spelling. Reload needs to
preserve canonical identity so separately stored references can reattach to the same
blocks.

The native representation still must not become another document owner. The live
canonical block tree and mutation invariants remain owned by `SlopadEditorDocumentModel`; a codec
only transforms an immutable complete projection. Files, URLs, databases, cloud records,
encryption, autosave, conflicts, recovery, retries, atomic replacement, application
document identity, and storage revisions differ by host and have no editor-semantic owner
inside SlopadEditor.

One current Core behavior makes the decoder boundary especially important.
`BlockContent.init(from:)` constructs `BlockContent`, whose initializer clamps mark ranges,
drops empty marks, merges overlapping or adjacent marks of the same kind, and sorts the
result. Decoding archive JSON directly into `EditorBlockInput` would therefore allow
malformed stored content to become apparently canonical without an error. Persistence must
fail closed before any normalizing core initializer runs.

## Decision

### One opt-in pure codec, no storage abstraction

Add `SlopadEditorArchive` as a separate opt-in library product and target. Its target dependency
is only `SlopadEditorCoreModel`; Foundation contributes `Data`. Source files that declare the
public codec API use Swift 6 `public import SlopadEditorCoreModel` so the underlying public types
are legal in public declarations, then the archive module curates exactly these aliases:

```swift
public import SlopadEditorCoreModel

public typealias BlockID = SlopadEditorCoreModel.BlockID
public typealias BlockKind = SlopadEditorCoreModel.BlockKind
public typealias BlockContent = SlopadEditorCoreModel.BlockContent
public typealias TextRange = SlopadEditorCoreModel.TextRange
public typealias EditorBlockInput = SlopadEditorCoreModel.EditorBlockInput
```

Nested public vocabulary such as block-kind payloads and inline-mark kinds remains reachable
through its aliased parent type; it does not receive another top-level alias. This is a
curated archive facade, not a `SlopadEditorCoreModel` product or a blanket
`@_exported import`. `SlopadEditorArchive` does not copy or wrap these values, require
`SlopadEditorEngine`, or make Session, AppKit, SwiftUI, TextKit, filesystem APIs, URLs, databases,
and storage providers dependencies or public vocabulary.

The codec is synchronous, stateless, deterministic in meaning, and safe to call in any
isolation domain that owns its input values. It performs no I/O, launches no task, retains
no document, and offers no repository or autosave protocol. `SlopadEditorAppKit` and
`SlopadEditorSwiftUI` do not re-export it.

The intended public call sites are the complete public surface:

```swift
import Foundation
import SlopadEditorArchive

let data: Data = try SlopadEditorArchive.encode(snapshot.blocks)
let blocks: [EditorBlockInput] = try SlopadEditorArchive.decode(data)
```

Every `EditorBlockInput`, `BlockID`, `BlockKind`, `BlockContent`, and `TextRange` appearing
in this API is the exact `SlopadEditorArchive` alias above. Therefore `snapshot.blocks` obtained
through any public UI or Engine facade is type-identical and crosses this boundary without
conversion.

The API draft is:

```swift
public enum SlopadEditorArchive {
    public static func encode(
        _ blocks: [EditorBlockInput]
    ) throws(SlopadEditorArchiveEncodingError) -> Data

    public static func decode(
        _ data: Data
    ) throws(SlopadEditorArchiveDecodingError) -> [EditorBlockInput]
}

public enum SlopadEditorArchiveEncodingError: Error, Hashable, Sendable {
    case canonicalInvariant(SlopadEditorArchiveCanonicalInvariant)
}

public enum SlopadEditorArchiveDecodingError: Error, Hashable, Sendable {
    case malformedData
    case unsupportedFutureVersion(found: Int, latestSupported: Int)
    case unsupportedPastVersion(found: Int, earliestSupported: Int)
    case canonicalInvariant(SlopadEditorArchiveCanonicalInvariant)
}

public enum SlopadEditorArchiveCanonicalInvariant: Hashable, Sendable {
    case emptyDocument
    case duplicateBlockID(BlockID)
    case invalidContent(blockID: BlockID)
    case missingParent(blockID: BlockID, parentID: BlockID)
    case cycleDetected(BlockID)
    case noncanonicalDepthFirstOrder
}
```

Concrete error names may receive ordinary API-guideline spelling cleanup during
implementation, but the four decoding categories and their fail-closed meaning are fixed.
There is no partial success value. Malformed JSON, an unsupported version, or a canonical
invariant failure returns no blocks; invalid input returns no archive bytes.

Only `Data`, the five curated `SlopadEditorArchive` aliases above, and archive-owned error values
cross this public boundary. Public signatures and associated error values use those exact
aliases. `EditorSession`, `EditorDocumentSnapshot`, epoch, revision, selection,
AppKit/SwiftUI/TextKit types, `URL`, database/storage protocols, raw
`SlopadEditorCoreModel` imports, and package-only `Document`/`Block` types do not.

### Version 1 wire contract

Version 1 is UTF-8 JSON with exactly two top-level members:

```json
{
  "formatVersion": 1,
  "blocks": [
    {
      "id": "title",
      "parentID": null,
      "kind": { "type": "heading", "level": 1 },
      "content": {
        "text": "Slopad",
        "marks": [
          {
            "kind": { "type": "strong" },
            "range": { "lowerBound": 0, "upperBound": 6 }
          }
        ]
      }
    }
  ]
}
```

`blocks` is the complete canonical parent-before-child depth-first preorder. Array order
is both root order and sibling order. Each block preserves its exact `BlockID.rawValue`,
optional parent identity, complete `BlockKind`, text, and canonical inline marks.

The v1 `kind.type` cases and associated fields are:

| Core value | Wire value |
| --- | --- |
| `.paragraph` | `{"type":"paragraph"}` |
| `.heading(level:)` | `{"type":"heading","level":1|2|3}` |
| `.unorderedListItem` | `{"type":"unorderedListItem"}` |
| `.orderedListItem(restartNumber:)` | `{"type":"orderedListItem","restartNumber":null|Int}` |
| `.quote` | `{"type":"quote"}` |
| `.codeBlock(language:)` | `{"type":"codeBlock","language":null|String}` |
| `.divider` | `{"type":"divider"}` |
| `.todo(isChecked:)` | `{"type":"todo","isChecked":Bool}` |

The v1 mark `kind.type` cases are `strong`, `emphasis`, `code`, `strikethrough`, and
`link`; `link` additionally carries a `destination` string. Mark ranges use nonnegative,
half-open grapheme offsets into `content.text`, matching `TextRange` rather than UTF-8 or
UTF-16 offsets.

V1 also has internal admission budgets: at most 16 MiB of archive bytes, 150,000 parsed
JSON values, 100,000 total array elements, 100,000 total object members, 8 MiB of total
decoded UTF-8 string content, and nesting depth 128. These are format-safety limits that
bound allocation and parser work, not latency targets or universal document-size advice.
The values leave structural headroom over the 10,000-block smoke document (roughly 80,000
values and 70,000 members). The decoder checks cumulative budgets before collection or
string growth and reports excess as `malformedData`; the encoder preflights the same tree
budgets before Core canonical validation, without building document maps or projection
arrays. It refuses to return bytes using the locked `invalidContent` invariant for the first
block that would exceed the representable V1 budget.

The encoder may choose JSON whitespace, object-key ordering, slash escaping, and other
representation details. Those bytes are not an interoperability or hashing contract.
Semantic determinism means repeated encoding of the same canonical input describes the
same version, block preorder, identities, kinds, text, and marks; it does not promise
byte-for-byte identity across implementations, toolchains, or library releases. Tests
decode and compare the complete canonical values instead of comparing `Data` bytes.

The envelope contains no metadata beyond `formatVersion` and `blocks`. In particular it
does not contain selection, stored marks, undo/redo history, operation journal, external
reference payloads, Session epoch, committed revision, composition, slash/drag runtime,
layout, viewport, scroll, focus, TextKit state, file identity, storage revision, timestamps,
or host conflict metadata.

### Decode raw wire values before constructing normalizing core values

The decoder first parses archive-owned raw DTOs made from primitive JSON values and
archive-owned wire enums. It must not ask `JSONDecoder` to synthesize
`EditorBlockInput`, `BlockContent`, `BlockContent.InlineMark`, or `TextRange` directly.

Before constructing any `BlockContent`, the raw pass verifies:

- the v1 object shape, required members, member types, and known enum tags;
- object member names are unique at every level; a duplicate key is malformed rather than
  resolved by first-wins or last-wins parser behavior;
- every mark range is ordered, nonempty, nonnegative, and no greater than the text's
  grapheme count;
- every associated kind/mark value required by the tagged case is present and has the
  expected primitive type.

Unknown v1 members or enum cases fail as malformed data. V1 has no extension bucket where
unknown semantic content may be preserved. Only after raw validity succeeds may the codec
construct `TextRange` and `BlockContent.InlineMark` values. It passes those values through
a package-only strict CoreModel constructor before creating an `EditorBlockInput`:

```swift
package init(
    validatingCanonicalText text: String,
    marks: [BlockContent.InlineMark]
) throws(CanonicalBlockContentValidationError)
```

That constructor compares the supplied mark list with CoreModel's canonical order and
merge form, then assigns the already-canonical values without normalizing them. Duplicate,
overlapping, or adjacent ranges of the same kind, empty/out-of-bounds ranges, and a list
that would be reordered are rejected rather than merged, clamped, dropped, or sorted. The
archive target therefore does not copy CoreModel's exact mark-order/merge algorithm.

Only after the strict content construction succeeds may the codec create
`EditorBlockInput` values. It then invokes the shared canonical-input validator described
below. This staged order prevents core normalization from laundering malformed archive
data into a successful document. Invalid JSON/object shape maps to `malformedData`; a
well-typed mark list that is not canonical maps to
`canonicalInvariant(.invalidContent(blockID:))`.

### One selection-independent canonical validation seam

`SlopadEditorCoreModel` owns the canonical input invariant because both
`SlopadEditorDocumentModel` document replacement and the CoreModel-only archive target need the
same answer. The implementation extracts a package-level, selection-independent seam:

```swift
package enum CanonicalDocumentInput {
    package static func validate(
        _ blocks: [EditorBlockInput]
    ) throws(CanonicalDocumentInputValidationError)
}
```

The package error contains the six archive-visible invariant cases above. It rejects an
empty document, duplicate IDs, noncanonical content, a missing parent, a cycle, and any
array that is not canonical depth-first preorder. A child preceding its parent is therefore
rejected as noncanonical preorder even if that parent occurs later in the array.

`SlopadEditorArchive.encode` validates before writing. `SlopadEditorArchive.decode` performs raw wire
validation, constructs core values, then validates before returning. Model replacement
calls the same seam and separately validates its requested selection. Selection does not
enter the shared validator or archive API, and the archive target does not duplicate model
tree validation.

The exact package type name may be adjusted with the implementation file layout, but its
access, selection independence, callers, and error mapping are fixed. The strict
`BlockContent` constructor and document-input validator are genuine cross-target invariant
contracts, not public host APIs and not a generic CoreModel helper bucket.

### Version evolution and migration

`SlopadEditorArchive` owns wire-version recognition and pure in-memory migration. A host must not
inspect a version and recreate SlopadEditor's canonical migration rules in file, database, or
cloud code.

- A decoder rejects versions above its latest supported version as
  `unsupportedFutureVersion` before reading their block payload as v1.
- A decoder rejects versions below its earliest still-supported version as
  `unsupportedPastVersion`. Version zero and negative versions are unsupported past
  versions; a missing, fractional, nonnumeric, or out-of-range version is malformed data.
- While an old version remains supported, its wire DTO is validated in its own schema,
  migrated through pure archive-owned DTO/value transforms, and validated as current
  canonical input before success.
- A source-compatible decoder broadening that maps additional legacy spelling to exactly
  the same canonical meaning may remain within the same format version. The v1 encoder
  continues to emit only the fixed v1 schema.
- Any newly emitted canonical field, required field, enum case, changed default, changed
  range coordinate, changed identity/order meaning, or other change an old decoder could
  lose or misinterpret is breaking and requires a new `formatVersion` plus a migration
  decision.
- Removing decode support for a past version is a deliberate library compatibility change,
  never a silent reinterpretation as the current version.

The host may wrap archive bytes with encryption, compression, checksums, or storage
metadata, but that wrapper is outside the archive schema and cannot change the canonical
meaning of successfully decoded blocks.

### Host persistence flow and concurrency boundary

ADR 0008 keeps each mutable Session on one executor; the codec does not weaken that rule.
The intended debounced autosave path is:

1. A committed model change produces `EditorUpdate.committedDocumentRevision`.
2. The host records the `(EditorSessionEpoch, EditorDocumentRevision)` only as an
   in-process freshness token and coalesces notifications using its own debounce policy.
3. When the debounce fires, the host synchronously reads the latest
   `documentSnapshot` on the Session-owning executor.
4. The host transfers the immutable `Sendable` `snapshot.blocks` value to its chosen
   background executor and calls the synchronous pure encoder there.
5. Snapshot capture synchronously registers its storage token in one host-owned admission
   authority before posting background work. Final admission, the atomic replacement, and
   publication of the persisted token are one throwing operation protected by that same
   authority; a failed or stale operation cannot publish success. A newer capture that races
   an admitted filesystem replacement waits for that indivisible commit, then registers
   synchronously and invalidates the older persisted authority before its background task
   enters the actor mailbox. Holding this gate during a filesystem rename can delay capture
   registration, so hosts should prepare bytes and temporary files before admission and keep
   the protected operation to the final atomic store boundary.
6. The host performs its own atomic file/DB/cloud write, retry, storage-revision update,
   conflict handling, and user-visible recovery. A newer revision observed after a write
   begins keeps the document dirty and queues the newer save. When a persistence outcome is
   delivered, the Session-owning executor rechecks the exact current token, document ID, and
   generation, so completion of an older write cannot mark the newer revision persisted.

Epoch/revision prevents an older in-flight encode from overwriting a newer in-process
snapshot. It is never placed in the archive and is not a persistent or database revision.
A host storage revision remains a separate host value with separate conflict semantics.

During live composition, public persistence continues to read the last committed document
and revision. This remains true if the future ADR 0014/#76 implementation updates
transaction-local canonical editing content: composition close publishes the changed
committed document and revision together. Debounced autosave may therefore retain the
prior committed snapshot while composition is open. An explicit save, document switch, or
close first uses the synchronized composition-flush boundary, then captures the resulting
committed snapshot.

### Identity survives; editor runtime does not

Successful archive round-trip preserves every `BlockID`. A host-owned reference stored
separately may reattach after reload by looking up that stable ID, and must handle the ID
being absent after ordinary later editing. Reference payloads themselves are not placed in
the archive.

Selection and history do not restore. They are canonical editor state with a different
lifecycle, not canonical document content. A host starts or replaces a Session from the
decoded blocks using the existing lifecycle contract and chooses an ordinary initial
selection through that contract; the codec never manufactures one. Undo/redo history,
Session epoch/revision, and composition runtime begin with the new Session lifecycle.

The archive bytes, decoded DTOs, and host persistence records are representations of the
one canonical document, not independently mutable document stores. All editing continues
through `SlopadEditorDocumentModel` transactions after load. Neither the codec nor the host storage
layer acquires command, invariant, selection, or history ownership.

## Consequences

- Native reload preserves block identity, unlike Markdown import/export.
- Archive corruption and incompatible versions fail without partial blocks or silent
  normalization.
- Encoding may run away from the Session executor after the host captures immutable blocks;
  I/O and stale-write suppression remain host policy.
- `Fixtures/DownstreamArchiveHost` includes an archive codec-surface target/source whose only package
  product dependency is `SlopadEditorArchive` and whose source imports only Foundation and
  `SlopadEditorArchive`. It constructs the aliased block/kind/content/range/mark vocabulary and
  round-trips it through the codec, proving that no raw CoreModel or Engine import is
  needed.
- The same fixture proves host lifecycle integration separately. Its lifecycle target/source may
  additionally import exactly one public UI facade plus `SlopadEditorArchive`, passes the
  facade's type-identical `snapshot.blocks` directly to the codec, and never imports raw
  `SlopadEditorEngine`, `SlopadEditorCoreModel`, or package-only types. If both probes live in one
  fixture package, they remain separate targets/sources with distinct product dependencies
  and import audits. Neither ordinary AppKit/SwiftUI lifecycle fixtures nor the Markdown
  fixture gains an archive dependency.
- Adding encryption, cloud sync, attachments/blobs, incremental journals, streaming,
  partial loading, collaboration/CRDT, or a storage protocol requires a separate owner
  decision. None is implied by this archive.
- Byte-exact external interoperability, signed-byte hashing, or a canonical binary format
  would require a new ADR rather than strengthening v1 JSON after implementation.

## Related decisions

- [ADR 0008](0008-keep-editor-session-executor-confined.md) — Session executor confinement
- [ADR 0009](0009-publish-committed-document-snapshots.md) — committed full-document source
- [ADR 0012](0012-host-embedding-contract.md) — ordinary host and opt-in codec boundaries
- [ADR 0013](0013-markdown-format-boundary.md) — Markdown semantic identity discontinuity
- [ADR 0014](0014-latch-selection-mode-and-support-cross-block-text.md) — committed
  composition publication rule
