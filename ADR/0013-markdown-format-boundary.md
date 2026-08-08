# 0013 - Depend on swift-markdown Behind a Format Target, and Guarantee Semantic Round-Trip Only

Date: 2026-08-08

## Status

Accepted

## Context

Slopad has no external dependencies. `Package.swift` declares none, and every target is
built from sources in this repository. Adding a Markdown parser changes that, and two
questions have to be answered before any adapter code exists — issue #29, blocking #30.

**First: what does depending on `swift-markdown` actually cost?** The handoff document
listed "pin version and minimum toolchain" as undecided and then scheduled the adapter work
as if the dependency were a line item. It is not; it is a change to the package graph, which
is the same class of decision as ADR 0002.

**Second: what does round-trip mean?** `**bold**` and `__bold__` describe the same emphasis.
If the canonical document holds `.strong` over a range and the encoder writes one spelling,
a document that arrives with the other spelling comes back changed. Whether that is
acceptable determines whether Markdown can be a storage format at all, and the persistence
choice was left waiting on an answer that was never given.

## Measurements

Taken against `swift-markdown` 0.8.0 with a probe package rather than estimated.

| | |
| --- | --- |
| Resolved version | `swift-markdown` 0.8.0, released 2026-05-07 |
| Transitive | `swift-cmark` 0.8.0 — a C library (cmark-gfm) |
| Its manifest | `swift-tools-version:6.2` |
| Slopad's manifest | `swift-tools-version:6.0` — unchanged; SwiftPM accepts the mixed versions |
| Cold build | 109 files, ~10s on an 8-core arm64 machine |
| Strict concurrency | Clean. A concrete `Document` and an `any Markup` existential both cross a `Task` boundary without diagnostics under `-strict-concurrency=complete` |

The one real constraint is not in the table's first column. `swift-markdown`'s manifest is
`6.2`, so **the toolchain building Slopad must be able to parse a 6.2 manifest — Swift 6.2 or
later** — even though Slopad's own tools version stays at 6.0. That is the minimum-toolchain
answer #29 asked for.

The strict-concurrency result is worth stating plainly because it removes a risk that was
assumed: there is no `Sendable` friction to design around. The isolation rule below is not
motivated by concurrency.

## Decision

### The dependency lives behind one target

`SlopadMarkdown` depends on `SlopadCoreModel` and on `swift-markdown`. Nothing else in the
package depends on `swift-markdown`.

Its public surface is expressed entirely in core vocabulary — `EditorBlockInput`,
`BlockContent`, `BlockKind`, `BlockContent.InlineMark`, and diagnostics defined in that
target. `Markdown.Document`, `Markup`, `Paragraph`, `Strong`, `Emphasis`, and every other
parser type stay inside it.

The reason is not concurrency and not extensibility. It is that a parser AST is a *format's*
model of a document, and letting it reach `EditorSession` or `BlockLayout` would put Markdown
syntax where ADR 0003 keeps TextKit out — a layer answering questions in some other system's
terms. Confining it to one target makes the compiler enforce that instead of a review
convention.

`swift-markdown` is pinned `from: "0.8.0"`. It is pre-1.0, so a minor bump can break source;
the pin is a floor to be raised deliberately, and `Package.resolved` is what actually fixes
the build.

### Round-trip is semantic, not byte-exact

**A document encoded to Markdown and decoded again is equal in meaning. Nothing guarantees
the bytes are the same.**

Concretely, the guarantee is one direction:

```
decode(encode(document)) ≡ document        보장한다
encode(decode(markdown)) == markdown       보장하지 않는다
```

`≡` compares block structure — kind, parent, sibling order — and content — text and inline
mark ranges. It does **not** compare `BlockID`s: decoding produces fresh ones, because plain
Markdown has nowhere to carry them.

What this permits, deliberately:

- `**bold**` and `__bold__` both decode to `.strong` and encode to whichever spelling the
  encoder prefers. A user's choice of delimiter is not preserved.
- Insignificant whitespace, list marker style, and heading style may normalize.

What it forbids:

- Losing an inline mark, a block, or an ordering.
- Silently dropping a construct. Anything the encoder cannot express is reported as a
  diagnostic (ADR to follow with the encoder in #32), never omitted quietly.

### Consequence for persistence, stated now rather than discovered later

`BlockID`s do not survive a Markdown round-trip. `EditorDocumentPatch` uses them for its
compare-and-swap, and an agent referring to a block by ID across a save would be referring to
nothing.

So **Markdown is an import and export format, not a storage format**, unless a future
decision adds a sidecar carrying identity. That choice is not made here; what is settled is
that it cannot be avoided by claiming Markdown alone is sufficient.

## Consequences

- `swift-markdown` may not be added to any other target. A second target needing Markdown
  means `SlopadMarkdown` is missing an API, not that the dependency should spread.
- Building Slopad now requires a Swift 6.2 or later toolchain. Record this wherever build
  requirements are stated.
- Round-trip fixtures assert semantic equality with `BlockID`s excluded. A fixture asserting
  byte equality is testing something this ADR does not promise and should be rejected.
- The encoder owes a diagnostic for every construct it cannot express. "It round-trips" is
  not sufficient if the way it round-trips is by discarding.
- Raising the `swift-markdown` floor is a deliberate change with its own review, not a
  routine bump, while the dependency remains pre-1.0.
