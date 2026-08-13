# Loop Request Template

Use this template when asking for a bounded SlopadEditor work loop.

A loop is not just a longer prompt. It is a repeated cycle of:

`evidence -> candidate change -> verification -> result record -> reusable learning`

The request should make these boundaries explicit before editing starts:

- work type
- loop driver
- completion criteria
- owner / human decision boundary
- verification surface
- durable learning to record

## Template

```md
## Work Type

Choose one:

- Structure change
- Bug fix
- Performance change
- AppKit adapter surface cleanup
- Documentation/glossary alignment
- Test/evaluation hardening
- Agent harness/context improvement

## Loop Driver

Choose one:

- Turn-based: one bounded task, stop when the requested change is complete or context is missing.
- Goal-based: repeat until observable completion criteria pass, or the max attempts is reached.
- Time-based: re-check an external surface on an interval.
- Proactive: recurring, well-defined work with no human in real time.

- Driver:
- Max attempts / turn cap:
- Stop condition:
- Abort condition:

## Focus

- Area:
- Files, targets, or symbols to inspect first:
- What should stay out of scope:
- Existing behavior that must not change:

## Problem Or Risk

- Current symptom, friction, cleanup pressure, or user-facing failure:
- Why this matters to the app/user/workflow:
- Suspected owner:
- Known constraints:
- Known unknowns:

## Owner Boundary & Human Gate

- Canonical owner to preserve or clarify:
- Decisions the loop may make:
- Decisions that require human judgment:
- Architecture/product tradeoff to bring back instead of deciding silently:

## Completion Criteria

Write at least three observable criteria.

Prefer criteria that can be tested, measured, clicked, inspected, or reviewed. Avoid
criteria that only say "make it better" or "clean it up".

- [ ] User-facing behavior, boundary, or document state that must be true:
- [ ] Test, build, benchmark, trace, or audit that must pass:
- [ ] Scope or non-goal that must remain unchanged:
- [ ] Failure or edge case that must be covered:
- [ ] Durable record updated if the loop discovers reusable knowledge:

## Evidence To Gather First

Gather evidence before editing. If evidence is weak, report the gap before proposing
a large change.

- Producer:
- Consumer:
- Fields or facts carried across the boundary:
- Existing tests, docs, benchmarks, traces, or call sites to verify:
- Representative failing or risky scenario:
- User-visible workflow to click/run/inspect:
- Current baseline result, if measurable:
- Similar past failure or rule to reuse:

## Candidate Change Plan

Before implementation, state the smallest plausible change.

- Candidate change:
- Layer affected:
  - Model behavior expectation
  - Harness: prompt, tool, workflow, script, test, benchmark, CI
  - Context: docs, glossary, owner map, failure log, project convention
  - Product code
- Why this layer is the right one:
- Deletion, merge, or access-shrink attempt to try first:
- Regression risk:

## Loop To Run

For structure changes:

`owner decision -> type inventory -> deletion/merge/access-shrink experiment -> deletion test -> place surviving types by owner/read intent -> verification -> durable doc update`

For bug fixes:

`symptom -> canonical owner -> why tests missed it -> focused test -> fix -> full verification -> failure-log/doc rule proposal`

For performance changes:

`hot-path hypothesis -> baseline benchmark at 100/1000/10000 -> candidate change -> counter check -> CSV/doc update -> regression risk record`

For AppKit adapter surface cleanup:

`adapter boundary inventory -> AppKit-only responsibility check -> core leakage check -> shrink public surface -> compile/test -> glossary or owner-map update`

For documentation/glossary alignment:

`term inventory -> canonical definition -> conflicting usage check -> doc update -> code/comment reference check -> rule for future requests`

For test/evaluation hardening:

`missed behavior -> evaluator gap -> deterministic check -> focused test/benchmark/script -> prove it fails before fix when possible -> prove it passes after fix -> add durable rule`

For agent harness/context improvement:

`repeated failure pattern -> prompt/tool/doc/context hypothesis -> candidate rule or skill -> trial on small slice -> measure result -> keep/iterate/drop -> record outcome`

## Verification

Use layered verification. Do not rely on a single green check if the change touches
behavior users can observe.

- Focused check:
- Full check:
- User-facing/manual scenario:
- Build/test command:
- Benchmark or CSV update needed:
- Documentation/glossary/failure-log update needed:
- Second-review needed:
- Evidence to include in final response:

## Result Record

After the loop, report what happened so future loops can reuse it.

- Shipped / iterated / dropped:
- What changed:
- What was verified:
- What failed or was inconclusive:
- What reusable rule was learned:
- What should be avoided next time:
- Human decision still needed:
```

## Short Example

```md
## Work Type

Structure change

## Loop Driver

Goal-based

- Driver: repeat until ownership and verification criteria pass.
- Max attempts / turn cap: 3
- Stop condition: `swift test --quiet` and `git diff --check` pass, and surviving type placement is justified by owner/read intent.
- Abort condition: changing AppKit drawing behavior becomes necessary.

## Focus

- Area: `SlopadEditorBlockLayout/TextLayout`
- Files, targets, or symbols to inspect first: `TextLayoutCache`, `BlockMeasureRequest`
- What should stay out of scope: AppKit drawing behavior
- Existing behavior that must not change: rendered text measurement results

## Problem Or Risk

- Current symptom, friction, cleanup pressure, or user-facing failure: text measurement helpers may be placed by folder name instead of producer/consumer ownership.
- Why this matters to the app/user/workflow: misplaced helpers make later layout changes harder to verify and easier to route through the wrong module.
- Suspected owner: `SlopadEditorBlockLayout`
- Known constraints: keep `BlockTextLayoutProtocol` in `SlopadEditorCoreModel`.
- Known unknowns: whether `TextLayoutCache` is a reusable boundary or only an implementation detail.

## Owner Boundary & Human Gate

- Canonical owner to preserve or clarify: `SlopadEditorBlockLayout`
- Decisions the loop may make: move internal helpers, shrink access levels, delete unused types.
- Decisions that require human judgment: changing public layout protocol responsibilities.
- Architecture/product tradeoff to bring back instead of deciding silently: any change that alters AppKit drawing behavior.

## Completion Criteria

- [ ] Surviving types are placed by owner/read intent, not folder symmetry.
- [ ] A deletion, merge, or access-shrink attempt is checked before keeping a helper.
- [ ] `swift test --quiet` and `git diff --check` pass.
- [ ] No AppKit drawing behavior is intentionally changed.
- [ ] Any reusable ownership rule is proposed for the glossary or architecture docs.

## Evidence To Gather First

- Producer: text measurement request builder
- Consumer: block layout calculation
- Fields or facts carried across the boundary: attributed string, width, measurement options, cache key
- Existing tests, docs, benchmarks, traces, or call sites to verify: layout tests, relevant docs, call sites of `BlockMeasureRequest`
- Representative failing or risky scenario: helper used from both core and layout without a clear owner
- User-visible workflow to click/run/inspect: none; verify through tests and owner-map/doc review
- Current baseline result, if measurable: current test result
- Similar past failure or rule to reuse: prefer owner/read intent over folder symmetry

## Candidate Change Plan

- Candidate change: try shrinking helper visibility before moving it across modules.
- Layer affected:
  - Product code
  - Context: owner map or glossary
- Why this layer is the right one: the risk is ownership ambiguity, not model behavior.
- Deletion, merge, or access-shrink attempt to try first: make helper internal/private where possible.
- Regression risk: accidental protocol responsibility drift.

## Loop To Run

`owner decision -> type inventory -> deletion/merge/access-shrink experiment -> deletion test -> place surviving types by owner/read intent -> verification -> durable doc update`

## Verification

- Focused check: targeted layout-related tests
- Full check: `swift test --quiet`
- User-facing/manual scenario: not needed unless rendering behavior changes
- Build/test command: `swift test --quiet`
- Benchmark or CSV update needed: no
- Documentation/glossary/failure-log update needed: yes, if a reusable owner rule emerges
- Second-review needed: yes, if public protocol placement changes
- Evidence to include in final response: diff summary, attempted deletion/access shrink, checks run

## Result Record

- Shipped / iterated / dropped:
- What changed:
- What was verified:
- What failed or was inconclusive:
- What reusable rule was learned:
- What should be avoided next time:
- Human decision still needed:
```
