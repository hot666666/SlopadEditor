# AGENTS.md

Entry point for agents working in SlopadEditor.

## Read First

Use repository documents by purpose:

* `README.md` — package map and public usage
* `docs/ARCHITECTURE.md` — ownership, dependency rules, runtime flow
* `ADR/` — durable architecture decisions
* `docs/ROADMAP.md` — roadmap and open risks
* `docs/LESSONS_LEARNED.md` — repeated structural failure patterns

Read only documents relevant to the task.

Two different questions have two different authorities:

* **What the code does today** — current source and tests are authoritative. Do not trust a stale plan, handoff, or prior conversation over them.
* **What the code should become** — `docs/ROADMAP.md`, `ADR/`, and the tracking issue are authoritative.

When source and an intent document disagree about *intent*, that is a planning defect, not a signal to ignore the document. Correct the document first (or open an issue), then change code. Do not silently follow either side.

`Slopad_Semantic_Editor_Architecture_Handoff.md` is a background record, not a work order.

## Architecture Rules

SlopadEditor is a headless native block editor engine. The canonical document is a block tree; Markdown/HTML are input/output formats, not the model.

Ownership:

* `SlopadEditorDocumentModel` — canonical document mutation, selection, commands, history
* `SlopadEditorBlockLayout` — block layout, visibility, hit-test, reveal geometry
* `TextLayout` — text measurement and text geometry
* `SlopadEditorEngine` / `EditorSession` — orchestration and editor semantics
* `SlopadEditorAppKitUI` — AppKit input/drawing/focus/scroll adapter
* `SlopadEditorAppKitTextKit` — TextKit2 backend
* `SlopadEditorDataStructure` — editor-independent data structures

Guardrails:

* Decide the owning layer before editing.
* Platform adapters must not own editor semantics or canonical state.
* `EditorModel` must not own or call `BlockLayout`; `EditorSession` coordinates them.
* IME/composition, layout, viewport, TextKit geometry, and render state are not canonical document state.
* `SlopadEditorCoreModel` is shared contract vocabulary, not a generic helper/projection bucket.
* Add public/cross-target types only when they represent a real contract or invariant.
* Use `public` for host API, `package` for genuine cross-target contracts, and internal access otherwise.

For details or exceptions, consult `docs/ARCHITECTURE.md` and the relevant ADR instead of inferring them.

## Working Rules

Before editing:

1. Run `git status --short`.
2. Inspect the current implementation and relevant tests.
3. Preserve unrelated user changes.
4. Identify the owner and completion criteria.

While editing:

* Prefer existing repository patterns.
* Keep changes scoped to the requested behavior.
* Prefer `rg` / `rg --files` for search.
* Use `apply_patch` for manual edits.
* Keep filenames responsibility-revealing.
* Do not weaken downstream fixtures with `@testable` or package-only access.

For bug fixes, add a focused regression test when practical.

After three materially different failed fix attempts, stop speculative editing and report the evidence, remaining candidate causes, and next diagnostic step.

## Agent Orchestration

Use one writer at a time, and never review a moving diff. The operational role definitions,
model settings, review flow, and current concurrency policy are in
[Agent workflow](docs/AGENT_WORKFLOW.md); `.codex/config.toml` and
`.codex/agents/*.toml` are their executable source of truth.

## UI Changes

UI work must preserve both native behavior and engine semantics.

Use:

* `SlopadEditorDebugApp` for input, focus, selection, IME, scrolling, hit-testing, and rendering changes.
* `SlopadEditorUIBenchmarkApp` for changes that may affect layout, redraw, caching, frame time, drag/reorder, or large-document interaction.

AppKit-specific behavior belongs in the adapter; semantic editing behavior belongs behind `EditorSession`.

## Tests

* Test the layer that owns the behavior.
* Use Korean `@Test("...")` descriptions.
* Use `// Given`, `// When`, `// Then`.
* Prefer focused unit tests before fuzz or broad smoke tests.

## Verification

The canonical baseline entrypoints for executable changes are:

```sh
swift test --quiet
git diff --check
```

Select the additional build, fixture, runtime, benchmark, and documentation gates from
[Testing](docs/TESTING.md). Do not claim verification that was not run.
