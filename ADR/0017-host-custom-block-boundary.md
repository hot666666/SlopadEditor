# 0017 - Admit host-defined custom blocks as opaque atomic leaves

Date: 2026-08-14

## Status

Proposed.

This record is a pre-implementation proposal. It is not a description of shipped behavior
and must not be cited as one. It names no type that exists in source today.

It is blocked on three open decisions — height authority, body hosting mechanism, and
focus policy — recorded as D1–D3 in
[Custom block design questions](../docs/CUSTOM_BLOCK_DESIGN_QUESTIONS.md). Those decisions
change the target graph, so this ADR cannot be accepted before they close.

## Context

Embedding apps need document blocks whose meaning belongs to the app rather than to the
editor. The first candidate consumer displays a Todo owned by the embedding app. That is a
different thing from the built-in `BlockKind.todo(isChecked:)` checklist item, which is
canonical editor content; the naming collision is itself a hazard worth stating once.

`docs/ROADMAP.md` keeps `BlockKind` and the inline mark vocabulary closed "until a concrete
consumer proves an extension/preservation contract", and
[Epic #67](https://github.com/hot666666/SlopadEditor/issues/67) lists a dynamic
`BlockKind`/plugin registry as a non-goal. The candidate consumer lives in a separate
downstream repository and is scheduled as Future work there, so it cannot supply the proof
on the schedule this design would need. Proof must therefore come from an in-repository
fixture and debug host, exactly as the Markdown and archive boundaries were proven.

Current source constrains the shape of any answer:

| Fact | Evidence |
| --- | --- |
| `BlockKind` is a closed enum with eight cases | `Sources/SlopadEditorCoreModel/Document/BlockKind.swift` |
| Exhaustive `BlockKind` switches span nine production files across seven targets | Markdown encoder, Archive V1 encoder/decoder/preflight, TextKit chrome metrics, AppKit chrome renderer, BlockLayout full pass, clipboard write plan, Session rendering |
| Every block, including the atomic `divider`, is measured through one narrow `BlockMeasuring` capability, cached on a key derived from the block's own values | `Sources/SlopadEditorBlockLayout/TextLayout/TextLayoutCache.swift:29-45, 83-102` |
| The capability split already reserves a place for "a future non-text block type" | `Sources/SlopadEditorCoreModel/Layout/BlockTextLayoutProtocol.swift:1-10, 69-74` |
| That capability is `Sendable` and synchronous; the shipped backend satisfies it with a lock-guarded context, not a view | `BlockTextLayoutProtocol.swift:13-15`, `TextKitLayoutContext.swift:8-10` |
| The only shipped atomic non-text leaf is `divider` | `BlockKind+TextCapability.swift:8-18`, `EditorSession+Rendering.swift:413-421` |
| The archive envelope pins `formatVersion:1` and fails closed on any other version | `ArchiveV1Encoder.swift:10`, `SlopadEditorArchive.swift:67-74` |
| Block chrome is draw-only into a clipped `CGContext` | `Sources/SlopadEditorAppKitUI/AppKitBlockChromeRenderer.swift:10-36` |
| Block hit routing has three regions | `Sources/SlopadEditorCoreModel/Interaction/BlockHitRegion.swift` |

Two recorded failure patterns bound the solution space.
`docs/LESSONS_LEARNED.md` — *Treating an Appearance Hook as a Whole Text Renderer Seam* —
forbids adding a second high-level paint hook, and *Moving Engine Semantics into Native
View/Input Hosts* forbids letting a native view decide caret, selection, composition, or
block transition meaning.

## Decision

Admit one canonical custom block as an opaque atomic leaf, under the following terms. Terms
P1–P8 are the parts this design considers settled; the parts it does not settle are listed
in the next section and gate acceptance.

**P1 — Canonical representation is opaque.** A custom block carries a stable host `typeID`,
a host `version`, and an opaque payload. The editor validates only common invariants —
identity, uniqueness, canonical order, leaf-ness, and a payload size budget — and never
decodes host meaning. Custom blocks are `isTextCapable == false` and hold no canonical
inline text or marks.

**P2 — First-version custom blocks are leaves.** They cannot contain child editor blocks.
Containers are a separate future decision with a separate invariant set.

**P3 — Providers are injected per editor instance.** There is no global registry, no
process-wide type table, and no dynamic discovery. This keeps the Epic #67 non-goal intact:
the closed `BlockKind` vocabulary gains one opaque case, not a plugin system.

**P4 — Unknown types are preserved exactly.** A block whose `typeID` has no registered
provider renders as a read-only unsupported placeholder and keeps its identity, type,
version, and payload byte-for-byte. It remains selectable, movable, copyable, and
deletable, because a document a host cannot reorganize is worse than one it cannot render.

**P5 — Reviewed patches preserve unknown custom blocks by default.** `applyDocumentPatch`
rejects a post-image that drops, retypes, reversions, or rewrites the payload of a custom
block whose provider is not registered, unless the caller holds an explicit host
capability. This is a new canonical replacement invariant in
`Document+CanonicalReplacementValidation`, not an etiquette rule for patch producers: an
assistant that round-trips a document through Markdown would otherwise silently delete
app-owned content.

**P6 — Format boundaries stay fail-closed.** `SlopadEditorMarkdown` encode and decode fail
with a typed diagnostic naming the unsupported `typeID`; the codec gains no host hook and
no lossy fallback. Host-specific conversion happens outside the codec, on canonical block
values, before encode or after decode. The structured clipboard carries the payload; the
plain-text fallback emits a deterministic placeholder rather than the payload bytes.

**P7 — The editor keeps every semantic surface.** Hover rail (`+`, drag handle, block
menu), hit routing, drag and drop, block selection, caret and text selection, text
rendering, and IME remain editor-owned. A provider renders its block body and nothing else.

**P8 — Image and table are built-in, not custom.** They become canonical editor
capabilities under [#50](https://github.com/hot666666/SlopadEditor/issues/50) and its
successors. Routing them through the host escape hatch would put two owners on the same
document meaning.

**P9 — AI results are not a block kind.** External Markdown decodes to canonical blocks and
enters through `documentContextSnapshot()` / `applyDocumentPatch(_:)` with the existing
epoch/revision/selection CAS. No AI-response block exists.

## What this ADR deliberately does not decide

These are blocking. Each changes which target owns a contract, so guessing one would
produce exactly the kind of intent/source disagreement `AGENTS.md` tells us to fix in the
document first.

- **D1 — Sizer isolation and inputs.** The measurement seam already exists and already
  reserves a place for a non-text block type. What is open is narrower: `BlockMeasuring` is
  `Sendable` and synchronous, and the shipped backend satisfies it with a lock-guarded
  layout context rather than a view, so a provider cannot size a block by asking a live
  `NSView` through it.
- **D2 — Body hosting mechanism.** `AppKitBlockChromeRenderer` cannot host interactive
  controls, and adding a second paint hook is a recorded failure pattern.
- **D3 — Focus and first-responder policy.** A host view that becomes first responder
  breaks the canvas `NSTextInputClient` contract that IME depends on.

## Amendments this ADR would require

Accepting it is not a local change. It amends four accepted records, and each amendment is
part of the same decision rather than follow-up cleanup:

| Record | Required amendment |
| --- | --- |
| [ADR 0012](0012-host-embedding-contract.md) | Test 3 currently forbids any host hook over native key, IME, pointer, reveal, or paint pipelines. A provider that draws a block body participates in paint, hit testing, and possibly focus. The test needs an explicit, narrow exception with its own boundary — or the mechanism must be reshaped until test 3 holds unchanged. |
| [ADR 0015](0015-version-native-archive-and-keep-storage-host-owned.md) | The archive envelope is `formatVersion:1` and fails closed on anything else. Custom blocks require V2 and a stated policy for what a V1 reader does with a V2 document, plus a payload budget inside the existing byte/depth/member budgets. |
| [ADR 0013](0013-markdown-format-boundary.md) | Adds an unsupported-custom-block diagnostic case; the fail-closed contract itself is unchanged. |
| `docs/ROADMAP.md`, `docs/ARCHITECTURE.md` | The closed-`BlockKind` settled constraint, the ownership table, and the runtime path table each gain the custom-block owner and path. |

## Consequences

- One opaque case is added to a closed enum, which is a smaller commitment than a registry
  but still forces nine exhaustive switches across seven targets to state an answer. Each
  answer is a boundary decision, not a compiler chore.
- The archive gains a version boundary that older readers cannot cross. That is the cost of
  storing host content in the canonical document at all.
- A document containing custom blocks cannot be exported to Markdown. Hosts that need
  export must convert their own blocks first, outside the codec.
- The editor gains its first contract where a host contributes pixels inside the canvas.
  Whatever D2 decides, that boundary is the one most likely to accumulate the failure
  patterns above, so it needs its own fixture rather than only unit coverage.
- Sequencing: this work starts after Epic #67 closes. It shares owners with the unfinished
  #70/#71/#74/#76 tracks, and canonical/IME/TextKit changes cannot safely run two writers.
