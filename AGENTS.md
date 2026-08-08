# AGENTS.md

Entry point for agents working in Slopad.

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

Slopad is a headless native block editor engine. The canonical document is a block tree; Markdown/HTML are input/output formats, not the model.

Ownership:

* `SlopadEditorModel` — canonical document mutation, selection, commands, history
* `SlopadBlockLayout` — block layout, visibility, hit-test, reveal geometry
* `TextLayout` — text measurement and text geometry
* `SlopadEngine` / `EditorSession` — orchestration and editor semantics
* `SlopadAppKitUI` — AppKit input/drawing/focus/scroll adapter
* `SlopadAppKitTextKit` — TextKit2 backend
* `SlopadDataStructure` — editor-independent data structures

Guardrails:

* Decide the owning layer before editing.
* Platform adapters must not own editor semantics or canonical state.
* `EditorModel` must not own or call `BlockLayout`; `EditorSession` coordinates them.
* IME/composition, layout, viewport, TextKit geometry, and render state are not canonical document state.
* `SlopadCoreModel` is shared contract vocabulary, not a generic helper/projection bucket.
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

The main agent is the orchestrator for issue work. It owns requirements, routing, state,
review handoff, and merge decisions. It does not edit product source during delegated
feature work; it may maintain orchestration configuration and documentation.

Use one writer at a time. Keep at most two subagents active, and parallelize only bounded,
independent read-only work. Never run a reviewer against a moving diff.

Route work by risk:

* `worker` — `gpt-5.6-terra` at `high`; narrow changes whose owner, behavior, and
  acceptance criteria are settled.
* `high_risk_worker` — `gpt-5.6-sol` at `high`; concurrency, IME, canonical state,
  TextKit, performance, memory pressure, public API, or cross-layer contract changes.
* `reviewer` — `gpt-5.6-terra` at `high`, read-only; the first fresh review of a stable
  diff, using focused probes instead of repeating a credible full verification matrix.
* `critical_reviewer` — `gpt-5.6-sol` at `xhigh`, read-only; only after `reviewer`
  reports a P1 and the writer fixes it. It rechecks that P1 and directly affected lines;
  it must not restart a broad review.

The normal state flow is:

```text
ready -> working -> stable review packet -> reviewing -> fixing or ready-to-merge
```

Additional constraints:

* Do not configure or automatically invoke a Sol `max` agent.
* Do not add a separate verifier agent; the worker owns stable-head verification and the
  orchestrator owns final integration verification.
* Use short, self-contained task packets instead of forwarding the entire conversation
  when spawning an agent.
* After a correction, rerun focused checks and only the invalidated verification gates.
* Batch status visualization after multiple merges or a material architecture-boundary
  change instead of spawning a visualizer for every task.

## UI Changes

UI work must preserve both native behavior and engine semantics.

Use:

* `SlopadDebugApp` for input, focus, selection, IME, scrolling, hit-testing, and rendering changes.
* `SlopadUIBenchmarkApp` for changes that may affect layout, redraw, caching, frame time, drag/reorder, or large-document interaction.

AppKit-specific behavior belongs in the adapter; semantic editing behavior belongs behind `EditorSession`.

## Tests

* Test the layer that owns the behavior.
* Use Korean `@Test("...")` descriptions.
* Use `// Given`, `// When`, `// Then`.
* Prefer focused unit tests before fuzz or broad smoke tests.

## Verification

Always:

```sh
swift test --quiet
git diff --check
```

For AppKit or public host API changes:

```sh
swift build --product SlopadAppKit --quiet
swift build --product SlopadAppKitTextKit --quiet
swift build --product SlopadAppKitUI --quiet
swift build --package-path Fixtures/DownstreamAppKitHost --product DownstreamAppKitHost --quiet
```

For UI/runtime changes:

```sh
swift build --product SlopadDebugApp --quiet
```

For performance-sensitive UI changes:

```sh
swift build --product SlopadUIBenchmarkApp --quiet
```

For package/target graph changes:

```sh
swift package dump-package
```

Do not claim verification that was not run.
