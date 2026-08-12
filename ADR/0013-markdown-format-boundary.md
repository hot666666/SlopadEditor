# 0013 - Depend on swift-markdown Behind a Format Target, and Guarantee Semantic Round-Trip Only

Date: 2026-08-08

## Status

Accepted

## Context

SlopadEditor has no external dependencies. `Package.swift` declares none, and every target is
built from sources in this repository. Adding a Markdown parser changes that, and two
questions have to be answered before any adapter code exists — issue #29, blocking #30.

**First: what does depending on `swift-markdown` actually cost?** The handoff document
listed "pin version and minimum toolchain" as undecided and then scheduled the adapter work
as if the dependency were a line item. It is not; it is a change to the package graph, which
is the same class of decision as ADR 0002.

**Second: what does round-trip mean?** `**bold**` and `__bold__` describe the same emphasis.
If the canonical document holds `.strong` over a range and the encoder writes one spelling,
a document that arrives with the other spelling comes back changed. Whether that is
acceptable constrains the later persistence choice, which was left waiting on a round-trip
answer that was never given.

## Measurements

Taken against `swift-markdown` 0.8.0 with a probe package rather than estimated.

| | |
| --- | --- |
| Probed version | `swift-markdown` 0.8.0, released 2026-05-07 |
| Resolved transitive version | `swift-cmark` 0.8.0 — a C library (cmark-gfm) |
| Upstream manifest | `swift-tools-version:6.2`; its targets explicitly use Swift 5 mode |
| SlopadEditor manifest | `swift-tools-version:6.0` — unchanged; its targets currently compile in Swift 6 mode |
| Cold build | 109 files, ~10s on an 8-core arm64 machine |
| `Sendable` | **`Document` and `Markup` do not conform.** What is allowed is narrower than "clean" — see below |

The one real constraint is not in the table's first column. `swift-markdown`'s manifest is
`6.2`, so **once #30 adds it, the toolchain building SlopadEditor must be Swift 6.2 or later** even
though SlopadEditor's own tools version stays at 6.0. That is the minimum-toolchain answer #29
asked for; this docs-only PR does not change the current build graph.

### What the `Sendable` result actually is

An earlier draft of this ADR recorded "clean, no `Sendable` friction". That was wrong, and it
was wrong in the dangerous direction — it would have told #30 there was nothing to design
around. The probe that produced it only sent a locally-parsed value into a `Task`, which
Swift's region-based isolation permits by proving exclusivity. It never asked whether the
type conforms.

It does not. `requireSendable(Document.self)` fails to compile. Re-probed from a Swift 6
client target, the boundary is:

| shape | result |
| --- | --- |
| Parse locally, send into a `Task`, do not touch the original again | allowed — region isolation proves exclusivity |
| Send a `Document` received as a parameter | **error** — `SendingClosureRisksDataRace` |
| Send a local value and keep using it afterwards | **error** — `SendingRisksDataRace` |
| Keep and use a value inside one actor or other isolation domain | allowed — it does not cross that domain |
| Share it as `Sendable` state | reachable only through an unchecked wrapper, i.e. unchecked |

So a parser value can be held and used inside one isolation domain, and region isolation can
move a disconnected local value once. It cannot satisfy a `Sendable` API or be shared
arbitrarily across domains. `swift-markdown` 0.8.0 itself explicitly selects Swift 5 mode;
SlopadEditor's targets compile in Swift 6 mode, so the adapter is a Swift 6 client of a Swift 5
dependency.

This independently supports the isolation rule below. Parsing and conversion execute inside
one caller isolation domain and return only core values; no AST crosses that boundary. An
API that returned an AST for a caller to walk would violate both the import boundary and the
concurrency design.

## Decision

### The dependency lives behind one target

`SlopadEditorMarkdown` is a separate, opt-in library product and target. Its target depends on
`SlopadCoreModel` and on the `Markdown` product from `swift-markdown`; it is not folded into
`SlopadEngine`, `SlopadAppKit`, or `SlopadEditorSwiftUI`.

Its public surface is expressed entirely in core vocabulary — `EditorBlockInput`,
`BlockContent`, `BlockKind`, `BlockContent.InlineMark`, and diagnostics defined in that
target. Every source file that uses parser types declares `internal import Markdown`.
Swift then rejects any `public` or `package` declaration in that file whose signature uses
`Markdown.Document`, `Markup`, `Paragraph`, `Strong`, `Emphasis`, or another parser type.
That is the compiler-enforced public API boundary.

SwiftPM target separation alone is not claimed to make the module physically unimportable:
a transitive module can still be visible to another target in the resolved graph. #30
therefore also adds a repository architecture test that requires every Markdown import to
be spelled `internal import Markdown` inside `Sources/SlopadEditorMarkdown` and rejects it anywhere
else under `Sources/`. A dedicated downstream fixture depends on the opt-in
`SlopadEditorMarkdown` product plus `SlopadEngine`, decodes through the public core-vocabulary API,
passes the resulting blocks through `EditorDocumentPatch` and `EditorSession`, and never
imports `Markdown`.

The reason is not concurrency and not extensibility. It is that a parser AST is a *format's*
model of a document, and letting it reach `EditorSession` or `BlockLayout` would put Markdown
syntax where ADR 0003 keeps TextKit out — a layer answering questions in some other system's
terms. The separate product names the boundary; `internal import Markdown` makes leakage
through its exported API a compiler error, and the architecture test guards off-target
imports that SwiftPM alone does not forbid.

`swift-markdown` is pinned with `exact: "0.8.0"`. It is pre-1.0, so a minor bump can break
source; raising the exact requirement is a deliberate reviewed change. A downstream root
that requires an incompatible exact version will fail dependency resolution; that is the
accepted cost of preventing an unreviewed pre-1.0 minor update. A root
`Package.resolved` still records the selected transitive graph, but it is not the pin: each
downstream fixture or host is its own resolution root and does not inherit SlopadEditor's lockfile.

That propagation is intentional. Once #30 adds the package dependency, every host resolving
SlopadEditor must resolve and parse `swift-markdown`'s manifest, so those roots need a Swift
6.2-or-later toolchain even if their own manifest uses an older tools version. Only a host
that selects the opt-in `SlopadEditorMarkdown` product needs to build and link its Markdown and C
targets. #30 updates the README requirement when that package-graph change lands.

### Round-trip is semantic, not byte-exact

**A supported document successfully encoded to Markdown and decoded again is equal in
meaning. Nothing guarantees the bytes are the same.**

Concretely, the guarantee is one direction:

```
decode(encode(document)) ≡ document        보장한다
encode(decode(markdown)) == markdown       보장하지 않는다
```

`≡` first requires equal block counts, then pairs blocks by canonical depth-first position,
not by ID. A block's parent path is the sequence of sibling indexes from the root; paired
blocks must have the same parent path, sibling order, full `BlockKind` value, text, and
normalized inline marks including each mark's kind, associated value, and canonical
`TextRange`. `BlockID` values themselves are excluded: decoding produces fresh ones because
plain Markdown has nowhere to carry them. This gives #30 and #32 one concrete comparator to
share without allowing a `zip` to ignore a trailing block.

What this permits, deliberately:

- `**bold**` and `__bold__` both decode to `.strong`; the encoder always emits `**bold**`.
  `.emphasis` prefers `_emphasis_`. When CommonMark delimiter rules would reinterpret that
  underscore spelling at a nested delimiter seam or an adjacent Unicode boundary, the
  encoder deterministically falls back to `*emphasis*`; it never emits a spelling that loses
  semantic content on decode. A user's delimiter choice is not preserved, and the same
  canonical document always chooses the same delimiters.
- Source-syntax whitespace that is not represented in `BlockContent.text`, plus list-marker
  and heading-marker style, may normalize. Every whitespace character that is part of
  canonical text is significant and compares exactly.

What it forbids:

- Losing an inline mark, a block, or an ordering.
- Silently dropping a construct in either direction.

Unsupported constructs are fail-closed. When decoding recognizes a block or inline node
that core vocabulary cannot represent — tables, images, and raw HTML are current examples —
the result contains typed diagnostics with source ranges and **no partial
`[EditorBlockInput]` success value**. It does not flatten the node to text, preserve raw
Markdown as canonical text, or omit it. When encoding encounters a canonical value it cannot
express, it likewise returns diagnostics and no successful Markdown value. #30 and #32 may
choose the concrete result-type names, but not weaken this all-or-nothing boundary.

### Consequence for persistence, stated now rather than discovered later

`BlockID`s do not survive a Markdown round-trip, so selection, undo, and external references
need separate consequences stated explicitly.

**Selection.** `TextPosition` names a `BlockID`, and `BlockSelection` holds `blockIDs`,
`anchor`, and `focus` as `BlockID`s. A selection captured before any Markdown decode/import
refers to nothing in its fresh output, even when that import happens in the same process.

**Undo history — not affected, which is worth stating so nobody defends against it.**
`EditorTransaction` carries whole `EditorState` values, and `replaceDocument` appends one
rather than clearing the stack. Undoing an import therefore restores the previous document
*with its original identities*, which is correct. The import creates an identity
discontinuity between two internally consistent states; the undo transaction keeps both.

**Agent references.** An agent may reuse a named block only while the same canonical identity
set remains current. A reference captured before a Markdown reload/import cannot name a
block after it, whether that boundary falls between turns or inside one process.

Worth being precise about the compare-and-swap boundary. `EditorSession+AssistantEditing`
gates on session epoch, committed revision, and exact selection equality. That selection may
contain `BlockID`s, so its CAS component is identity-bearing. The gate does not separately
compare the old document's complete ID set; incoming replacement IDs are checked later by
structural validation for duplicates, missing parents, and cycles. An earlier draft reduced
this nuance to "CAS is ID-based" and a later one overcorrected to "CAS does not compare
IDs". Neither is accurate. A selection or external reference captured before a Markdown
reload cannot be reused afterwards; undo remains safe because it restores the whole prior
state.

The persistence source of truth is now decided: a versioned native archive, not Markdown.
Markdown remains explicit whole-document import/export and therefore keeps its fresh-ID and
syntax-normalization contract.
[ADR 0015](0015-version-native-archive-and-keep-storage-host-owned.md) defines
`SlopadEditorArchive` as an opt-in pure codec whose target depends only on `SlopadCoreModel`; its
public facade exposes only the ADR's curated, type-identical archive aliases, not a
CoreModel product. It encodes a format version and canonical blocks, including their
identities, but never selection, undo/history, operation journal, epoch/revision,
composition, layout, viewport, or TextKit state. The embedding app owns files, databases,
cloud sync, autosave, conflicts, retries, and error UX. This ADR supplies the Markdown
identity facts that native-archive persistence must not weaken. The archive product remains
unimplemented;
[issue #78](https://github.com/hot666666/SlopadEditor/issues/78) tracks that implementation.

## Consequences

- Only `SlopadEditorMarkdown` declares or imports the `Markdown` product. A second target needing
  Markdown means the opt-in product is missing an API, not that the dependency should spread.
- Adding the package dependency in #30 raises the effective build-toolchain requirement to
  Swift 6.2 or later and updates the README then; this docs-only decision does not change the
  current package graph.
- Round-trip fixtures assert semantic equality with `BlockID`s excluded. A fixture asserting
  byte equality is testing something this ADR does not promise and should be rejected.
- Markdown's dedicated opt-in format-consumer fixture remains separate from the future
  archive format-consumer fixture and from the ordinary one-product AppKit/SwiftUI lifecycle
  fixtures. No fixture may make Markdown a persistence fallback.
- A selection captured before an import must not be reapplied after it. Undo needs no
  special handling: it restores whole states, identities included.
- The adapter converts to core types before returning and does not retain the AST. An
  explicit `internal import Markdown` makes parser-type leakage through `public` or `package`
  signatures a compile error; the non-`Sendable` AST is a separate reason to finish the
  conversion inside one isolation domain.
- Decoder and encoder failures return diagnostics without a partial success value. "It
  round-trips" is not sufficient if the way it round-trips is by discarding.
- Changing the exact `swift-markdown` version is a deliberate change with its own review,
  not a routine bump, while the dependency remains pre-1.0.
