# Lessons Learned

This document records repeated failure patterns from Slopad work, especially patterns
that prevented a task from succeeding in one pass. It is not the source of truth for the
current structure. Use `README.md` for the short structural map, `docs/ARCHITECTURE.md`
for the detailed ownership and extension philosophy, `AGENTS.md` for terminology and
responsibility criteria, `ADR/` for durable decisions, and `docs/ROADMAP.md` for current
development direction.

## Recording Criteria

- Do not add one-off bugs or regressions directly to this document. Lock them down with
  tests owned by the relevant layer.
- Treat a mistake that repeats twice as a candidate for `AGENTS.md` working principles or
  work-loop rules first.
- Add only failures that repeat across multiple slices or keep distorting structural
  judgment.
- Write entries as prevention questions and forbidden patterns, not as current solutions.
  Do not use stale type names, folder names, or benchmark numbers as current source
  evidence.

## Work Highlights

- The canonical model was set as a tree-capable block document, not Markdown text.
  `Document`/`Block` canonical values, selection, command, transaction, undo/redo,
  projection, and layout orchestration were elevated into engine semantics.
- The AppKit/TextKit2 reference path moved away from an `NSTextView` wrapper and toward a
  native surface that collects OS callbacks, forwards them as engine input, and draws
  engine snapshots.
- `EditorSession` became the host-facing facade, `SlopadEditorModel` the semantic editing
  owner, `SlopadBlockLayout` the layout projection owner, and `SlopadCoreModel` the public
  vocabulary plus package canonical value owner.
- The SwiftPM target graph now prevents `SlopadEditorModel` and `SlopadBlockLayout` from
  importing each other. `Session` translates semantic results into layout requests.
- Layout performance moved from a full-rebuild baseline through dirty edit, structural
  edit, visible-index mutation, render damage, and viewport-driven lazy measurement work.
  Benchmarks should compare 100/1000/10000 blocks and read counter columns together.
- Cleanup changed from folder organization to a type survival loop: inspect owner,
  access, fact kind, producer, consumer, and invariant; try delete/merge/access-shrink
  first; then place only the surviving types in owner/read-intent folders.

### Judging Structure by Folder Symmetry

Symptom: folders or wrappers are created because names such as `Input`, `Render`,
`Output`, `Snapshot`, or `Policy` look tidy.

Cause: the source tree shape was considered before producer/consumer flow.

Next time:

- Folder names are the final placement criterion.
- First write down the type's fact, owner, producer, consumer, and invariant.
- Add a new folder only when the read intent for surviving owner-local helpers is clear.

### Using `SlopadCoreModel` as a Common Bucket

Symptom: reducer, policy, layout cache, projection helper, or tree-aware document helper
types are moved into CoreModel just because several targets use them.

Cause: "shared" was confused with "shared vocabulary."

Next time:

- CoreModel admission passes only for host contracts, backend seams, or package canonical
  values.
- Do not promote a value unless producer, consumer, invariant, and dependency direction
  are all explainable.
- Moving a value into CoreModel because a deletion experiment became inconvenient is a
  failed slice.

### Widening Public/Package Surface for Test Convenience

Symptom: production interfaces are widened so tests can observe internal state.

Cause: behavior that should be verified through the owner interface was not separated from
owner-internal invariant checks.

Next time:

- `public` means host surface, and `package` means a real cross-target owner interface.
- Do not open an entire owner helper through `package extension`.
- Keep owner-internal invariant checks inside owner tests or narrow test support.

### Reducing TextLayout to a Height-Only Measurer

Symptom: `textLayouter` is treated like `textMeasurer`, or renamed that way.

Cause: the layout backend seam was assumed to cover only height, even though it also
covers line fragments, caret rects, selection rects, text hit-testing, and drawing
handoff.

Next time:

- Keep the `textLayouter` name.
- Keep concrete TextKit/AppKit objects in the backend/adapter, not in engine state.
- Do not mix block-local text geometry with document-wide y/height indexing.

### Treating an Appearance Hook as a Whole Text Renderer Seam

Symptom: a host appearance callback can skip, replace, or duplicate fragment text
(including effective marked content), selection, or caret feedback, or it receives
backend/session details that let it become a second native text pipeline.

Cause: backgrounds and block chrome were treated as equivalent to the coherent text
layout, geometry, input, and drawing contract.

Next time:

- Keep `AppKitBlockChromeRenderer` clipped, isolated, and limited to backgrounds,
  borders, gutters, and markers.
- Keep effective live composition in the TextKit2 fragment text pass, followed by the
  adapter-owned text selection and caret feedback pass.
- Treat layout, hit testing, caret/selection geometry, native text geometry, and drawing
  as one coherent backend contract.
- If a host needs complete replacement, build a separate platform adapter and backend
  around `EditorSession`; do not add another high-level paint hook.

### Moving Engine Semantics into Native View/Input Hosts

Symptom: AppKit views, delegates, `NSTextView`, or callback objects decide caret,
selection, composition, or block transition semantics.

Cause: OS callback sources were confused with the editor semantic owner.

Next time:

- Native surfaces translate OS facts into engine input and draw snapshots.
- The engine decides selection, marked-text lifecycle, insert/delete/Enter/Backspace/Tab
  semantics.
- Keep debug-only AppKit glue out of reusable packages until real reuse pressure exists.

### Pushing Complexity Elsewhere After a Deletion Experiment

Symptom: a type disappears, but the same invariant spreads into `Session`,
`SlopadCoreModel`, the demo host, test support, or multiple call sites.

Cause: deletion itself was treated as the success criterion.

Next time:

- If callers need to know more ordering, state, or decision-table details after deletion,
  the deletion failed.
- Check whether the situation needs a deeper owner interface instead of removal.
- If behavior change is required, split it from the cleanup slice.

### Importing External Architecture Names Directly

Symptom: names such as `view`, `plugin`, `operation`, `use case`, or `repository` from
ProseMirror, CodeMirror, Slate, Lexical, or Clean Architecture are copied into Slopad
folders.

Cause: external material was used as a template instead of a validator.

Next time:

- Extract principles from external references only.
- Translate them into Slopad through owner and call-path evidence inside the
  `UI -> Public API -> Session -> EditorModel / BlockLayout` structure.
- Do not import names without source/call-site evidence.

### Reading Benchmark Numbers as One Line

Symptom: performance improvement or regression is judged from one 10k number.

Cause: handle/render/layout/damage, visible projection, layout input count, cache
hit/miss, and index mutation count were not separated.

Next time:

- Read 100/1000/10000 together for layout hot paths.
- Read wall time and work counters together.
- Do not compare full rebuild, dirty incremental, structural incremental, and lazy
  measurement as if they were the same row.

### Treating Source/Test Layout as 1:1 Symmetry

Symptom: a test file is forced for every source file, or tests are moved because the
folders look asymmetric.

Cause: test layout was mistaken for file symmetry.

Next time:

- Tests mirror target/responsibility.
- Root package entrypoints or behavior that crosses several owner facts can stay in root
  tests.
- Use other-layer behavior as `Given` setup values; `When` should verify the behavior
  owned by that test file.

### Letting Formatting/Readability Cleanup Spread Too Far

Symptom: source-wide cleanup becomes formatting churn across more than 100 files.

Cause: repository style configuration and real owner boundaries were not checked first.

Next time:

- Check formatter rules first.
- Add `// MARK: -` only when a file has a real extension/helper boundary.
- Keep readability cleanup limited to currently relevant files and meaningful owner
  splits.

## Pre-Work Checklist

Do not edit yet if you cannot answer these questions before starting cleanup/refactor
work:

- Which owner target does this change belong to?
- What fact kind is this type/function/field: canonical, derived, command/event, cache,
  adapter result, or backend seam?
- Who is the producer, and who is the consumer?
- Which experiment comes first: deletion, merge, or access shrink?
- If it is deleted, does complexity disappear or spread into other callers?
- Does public/package surface become wider? If so, is there evidence for a host contract
  or cross-target owner interface?
- Does source/test/doc verification match the risk of this slice?

When blocked, restate the issue in this form instead of saying only "the name is weird":

```text
Symptom:
Cause hypothesis:
Owner:
Producer:
Consumer:
Deletion/merge/access-shrink experiment:
Where complexity will spread if it fails:
Verification:
```
