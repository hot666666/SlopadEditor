# Architecture Audit — 2026-08-13

Status: read-only audit record. Evidence, not a work order.

Base: `f059bc5` (`chore: rename package identity to SlopadEditor`), working tree clean
except `skills-lock.json`.

Scope: `SlopadEngine`, `SlopadAppKitUI`, `SlopadEditorModel`, `SlopadBlockLayout`, plus a
repository-wide documentation pass. Measured against [Architecture](ARCHITECTURE.md),
[ADRs](../ADR/README.md), [AGENTS.md](../AGENTS.md), and `Package.swift`.

This file records what was measured and what was found. It does not authorize changes.
Route follow-up work through [ROADMAP](ROADMAP.md) and the
[loop request template](LOOP_REQUEST_TEMPLATE.md).

## Headline

Boundaries are being respected. The dependency graph, target ownership, and naming are in
good condition; there were no architecture violations to clean up. The defects found were
in documentation, plus one cohesion hotspot and a set of over-wide `package` declarations.

| Axis | Result | Severity |
| --- | --- | --- |
| Dependency flow | No violations | — |
| Naming | Effectively clean | P3 |
| Ownership / responsibility | No clear violation | P3 |
| Complexity | One concentrated cohesion problem | P2 |
| Access levels | Over-exposure candidates | P2 |
| Documentation | Two genuinely broken references, one structural defect | **P1** |
| Verification | Continuous ADR 0012 gate red on `main` | **P1** |

The last row was not part of the requested scope. It was found while running the gates that
the documentation repair invalidated, and is the most serious item in this record.

## The Host Gate Was Broken on Local `HEAD`

`bash scripts/verify-host-surface.sh` — described in [Testing](TESTING.md) as "the canonical
continuous ADR 0012 gate on every pull request" — exited non-zero on an unmodified checkout
of `f059bc5`:

```
AppKit lifecycle fixture must depend on the SlopadAppKit product
  expected: 1
  actual:   0
```

Scope of the blast radius: `f059bc5` is **not pushed**. `origin/main` is `9bf4b65`, and the
last CI run of this workflow succeeded there. `.github/workflows/host-surface.yml` runs the
script on both `pull_request` and `push` to `main`, so the failure would have appeared on
the first push and not before. This was caught before it reached CI, not recovered after.

Two separate defects were found here. Only the first broke anything.

### Defect A — the gate script asserted the old package name (P1)

The fixture manifest was renamed correctly. The script that checks it was not:

```sh
# scripts/verify-host-surface.sh:83 — looking for a name the fixture no longer uses
count_matches '\.product\(name: "SlopadAppKit", package: "Slopad"\)' …
```

Because the assertion embeds the `package:` argument in its literal pattern, a correctly
renamed fixture stops matching and the gate fails closed — the right direction, on the wrong
signal. Lines 83 and 97 (AppKit and SwiftUI) were both affected. Repaired; the gate now
exits 0.

`verify-archive-surface.sh` was unaffected in both directions because its patterns match the
product name only (`product(name: "SlopadArchive")`) and never mention the package.

### Defect B — the archive fixture used an obsolete local alias (P3)

`Fixtures/DownstreamArchiveHost/Package.swift` still named `Slopad` in four places. This
broke nothing and could not have: `name:` in `.package(name:path:)` is a manifest-local
alias, and the same file's `package: "Slopad"` references matched it. Confirmed empirically
by reverting the file and asking SwiftPM:

```
dependency identity                              : slopad     ← from the directory name
dependency nameForTargetDependencyResolutionOnly : Slopad     ← the local alias
Build of product 'ArchiveCodecSurfaceProbe' complete!
```

So this was a naming inconsistency, not a failure. Repaired as part of the naming
unification, not as a gate fix.

**Reusable rule:** a rename is not complete when the package manifest and README are
updated. Grep the old identity across `scripts/`, `Fixtures/*/Package.swift`, and `justfile`
— and note that a *checker* can hold the old name just as easily as a checked file. Run
every gate in [Testing](TESTING.md), not only `swift test`.

## Method

Static measurement over `Sources/`, `Tests/`, `Debug/`, `Benchmarks/`, `Fixtures/`,
`docs/`, and `ADR/`:

- import graph extracted per target and compared against `Package.swift`;
- `public` / `package` / `open` declaration census per target;
- brace-depth function metrics (length, max nesting, branch tokens) over 957 functions;
- word-boundary reference search for each `package` declaration outside its declaring target;
- backticked-identifier extraction from prose docs, checked for existence in source;
- relative-link resolution across every Markdown file.

No tests, builds, or benchmarks were run. No performance claim is made below.

## Dependency Flow — no violations

The actual import graph matches `Package.swift` exactly across all twelve production
targets. No reverse or bypass dependency exists.

All four "important absences" asserted in [Architecture](ARCHITECTURE.md) hold in source:

| Asserted absence | Verified |
| --- | --- |
| `SlopadEditorModel` ↮ `SlopadBlockLayout` | yes |
| `SlopadAppKitTextKit` ↛ `SlopadEngine` | yes — `SlopadCoreModel` only |
| `SlopadMarkdown` ↛ `SlopadEngine` | yes |
| `SlopadArchive` ↛ `SlopadEngine` / storage | yes |

External framework confinement is also exact: `AppKit` appears only in the two AppKit
targets, `Markdown` only in `SlopadMarkdown`, `SwiftUI` only in `SlopadSwiftUI`.
`SlopadEditorModel`, `SlopadBlockLayout`, and `SlopadDataStructure` import nothing at all,
which is the strongest available evidence that the headless claim is real.

No action required on this axis.

## Naming — P3

Across 957 functions there are two type names matching common smell patterns, and both are
justified: `SlopadEditor.Coordinator` is the `NSViewControllerRepresentable` idiom, and
`AppKitEditorCanvasHandler` is a delegate protocol. No `Manager`, `Util`, `Helper`, or
`Service` type exists anywhere in `Sources/`.

The `handle*` prefix appears on roughly twenty functions but is applied consistently to
native-callback entry points, which makes it a convention rather than a defect.

No action required on this axis.

## Ownership — P3, no clear violation

The adapter was examined specifically for leaked editor semantics. What was found stays
inside the documented allowance:

- The selection helpers in `AppKitEditorViewController` (`selectedBlockIDs`,
  `activeTextPosition`, `activeChromeBlockID`) read `snapshot.selection` and project from
  it. That matches "must converge on Session facts without becoming semantics".
- `todoCheckboxHitRect` and floating-toolbar placement are named in
  [Architecture](ARCHITECTURE.md) as AppKit adapter chrome.
- No path mutates canonical state outside a model transaction.

## Complexity — P2

The problem is concentrated in one file rather than spread across the codebase.

`Sources/SlopadAppKitUI/AppKitEditorViewController.swift` is 1,821 lines — 1.8× the next
largest file — containing 98 functions, 38 stored properties, 11 `MARK` sections, and 7
extensions, and conforming to both `AppKitEditorCanvasHandler` and `AppKitActiveInputOwner`.
One type carries canvas handling, drawing, mouse events, native commands, native text
surface sync, the slash overlay, the formatting toolbar, native input ownership, and
pointer handling. This is a cohesion problem, not an ownership violation, and it is why
`SlopadAppKitUI` averages 291 lines per file.

The overall distribution is healthy: of 957 functions, 31 (3.2%) exceed 60 lines and 9
(0.9%) exceed 100 lines.

### A mechanical file split was attempted and rejected

Extracting the six trailing extensions into five topical files was tried and measured. It
reduced the main file from 1,821 to 1,117 lines, and the compiler then reported the exact
cost: **31 symbols had to be promoted from `private` to `internal`**, because Swift scopes
`private` to the file and every extension moved out of it lost access.

That trade is not worth taking as stated. The split relocates code without reducing
coupling: `AppKitEditorViewController` keeps every responsibility it had, while its
internal surface roughly doubles. It improves file length and navigation at the cost of the
encapsulation the audit was otherwise trying to tighten. The change was reverted.

The version worth doing is different work: extract **collaborator types** that own their own
state — a pointer-gesture controller and a chrome coordinator are the two obvious
candidates — so the responsibilities actually leave the class. That is a design change
requiring `SlopadDebugApp` behavioural verification, not a mechanical move, and it needs its
own [loop request](LOOP_REQUEST_TEMPLATE.md) packet.

For reference, the lowest-cost partial split measured was `Canvas Handling` (247 lines) plus
`Native Input Owner` (41 lines): both have zero reverse dependencies and together need about
8 promotions.

Deepest nesting is concentrated outside the audited targets — three of the five deepest
functions are in `SlopadMarkdown` (`validateTree`, `decodeInlineContent`,
`exceedsSupportedDepth`, each at nesting depth 5).

## Access Levels — P2

About 36 `package` declarations have no word-boundary reference outside their declaring
target, spread across `SlopadAppKitUI` (15), `SlopadEditorModel` (8), `SlopadEngine` (8),
`SlopadCoreModel` (3), and `SlopadBlockLayout` (2).

Verified example — `Sources/SlopadEngine/Session/CommandState/EditorCommandState.swift`:
the type exposes eight `package` members, but its only cross-target consumer,
`AppKitFloatingFormattingToolbar`, reads five (`detail`, `selectionMode`,
`clearInlineStylesAvailability`, `toggleState(for:)`, `availability(for:)`). The stored
properties `inlineStyleAvailability`, `inlineStyles`, `indentBlocksAvailability`, and
`outdentBlocksAvailability` are used only by the struct's own accessors.

**The 36 figure overstates the opportunity.** The scan cannot see enums consumed purely
through leading-dot syntax, because the type name never appears at the call site.
`EditorMixedValue`, `EditorCommandStateDetail`, and `EditorCommandSelectionMode` are
flagged but must stay `package`. Treat the list as candidates requiring per-item compile
verification, not as a demotion list.

## Documentation — P1

### Fixed in this pass

**`README.md` advertised a package name that does not exist.** Commit `f059bc5` renamed the
package to `SlopadEditor`, and two of three `.product(...)` snippets were updated. The
Native Archive snippet still read `package: "Slopad"`, so a host copying it from the public
README would fail to resolve the dependency.

**`SELECTION_INTERACTION_POLICY.md` mixed three kinds of material without distinguishing
them.** [Architecture](ARCHITECTURE.md) points at this file as the authority on the
implemented cross-block selection contract, but its 698 lines interleaved a normative
contract, a pre-implementation design proposal, and a completed gate checklist. Two
references were broken as a result:

- `EditorClipboardPlan` (design section) never shipped. The implementation landed as
  `EditorSession.clipboardWritePlan()` returning `EditorClipboardWritePlan`, with
  `EditorClipboardTextSlice` / `EditorClipboardBlockSubtrees` content. The same file's
  Implementation Closure section already named the shipped file, so the document
  contradicted itself.
- Gate 1 required "focused `SlopadEditorModelTests`", a target that does not exist. There
  are six test targets; `SlopadEditorModel` is exercised through `SlopadEngineTests`. The
  gate was literally unsatisfiable as written.

The proposed `EditorCommandState` sketch also referenced `EditorActionID` and
`InlineMarkKind`, neither of which exists in source.

The repair added a document map classifying each section's authority, status banners on the
design and gate sections, the shipped declarations in place of the sketches, and corrections
to both broken references.

**The visual companion carried the same defect.** `selection-interaction-map.html` rendered
its contract cards identically whether or not the type existed. `EditorClipboardPlan` was
corrected to `EditorClipboardWritePlan`, and `EditorDecorationSnapshot` — which never
shipped in any form, and whose consumers (search, comments, spellcheck, remote cursors) are
all unimplemented — is now labelled as an unimplemented proposal. Tag balance, the two
script selectors, and the page's self-contained asset policy were re-validated after the
edit; no browser or screenshot check was performed.

**GitHub URLs were spelled three ways.** The remote is `hot666666/SlopadEditor`. Docs
contained 13 occurrences of `/Slopad` (ADR 0012, 0013, 0014, 0015, ROADMAP, the policy
file) against 2 correct ones, and `ROADMAP.md` mixed both spellings within one file. Those
links survived only on GitHub's rename redirect, which breaks if the old name is ever
reclaimed. All 13 were rewritten; every non-handoff doc URL now reads `/SlopadEditor`.

### Remaining

**`Slopad_Semantic_Editor_Architecture_Handoff.md` is 2,227 lines** — 3.6× the combined size
of `ARCHITECTURE.md`, `ROADMAP.md`, and `AGENTS.md`. It carries 5 broken relative links
(three missing `references/*.png`, two literal `(url)` / `(…)` placeholders) and 13
references to the predecessor project name. `AGENTS.md` calls it "a background record, not a
work order", yet it is the most recently modified document in the repository.

### Product naming is unresolved, and one collision is already live

The rename in `f059bc5` changed package identity only. Every prose description still calls
the project **Slopad** — `README.md`, `AGENTS.md`, and `ARCHITECTURE.md` all open with
"Slopad is a …", all twelve modules use the `Slopad` prefix, and the debug and benchmark
windows title themselves `Slopad Debug` / `Slopad UI Benchmark`.

That is now known to be wrong: **Slopad is the name of the consuming application, and this
package is SlopadEditor.** Prose occurrences that name the project rather than a module are
small in number — about 28 across the main documents, 14 of them in
`SELECTION_INTERACTION_POLICY.md` — plus five user-visible strings and the handoff document.

One collision already exists and the rename makes it worse:

| Name | What it is |
| --- | --- |
| `Sources/SlopadEditorModel/` | the module owning canonical document mutation |
| `SlopadSwiftUI.SlopadEditorModel` | a `public final class` observable view model |
| `SlopadEditor` (package) | the package identity set by `f059bc5` |

`SlopadEditor` and `SlopadEditorModel` therefore each mean two different things depending on
whether the reader is thinking about modules or host API. A mechanical `Slopad` →
`SlopadEditor` prefix rename would produce `SlopadEditorEditorModel`, so the target scheme
has to resolve this deliberately rather than by substitution.

### Confirmed healthy

`ARCHITECTURE.md` and `README.md` have zero symbol drift — every backticked type and
function in them exists in source. `CLAUDE.md` is a symlink to `AGENTS.md`, so there is no
duplicated agent instruction file.

## Suggested Order

| # | Item | Axis | Size | Outcome |
| --- | --- | --- | --- | --- |
| 0 | Repair `verify-host-surface.sh` + archive fixture rename | verification | 6 sites | **done** — gate green |
| 1 | `README.md` package name | docs | 1 line | **done** |
| 2 | Policy doc section authority | docs | restructure | **done** |
| 3 | `EditorClipboardPlan`, Gate 1 target, HTML map cards | docs | 4 sites | **done** |
| 4 | Unify GitHub URL spelling | docs | 13 sites | **done** |
| 6 | Demote unconsumed `EditorCommandState` members | access | 4 members | **done** |
| 5 | Split `AppKitEditorViewController` | complexity | medium | **rejected** — see above |
| 7 | Extract collaborator types from the view controller | complexity | large | unowned, needs a packet |
| 8 | Audit remaining `package` demotion candidates | access | ~30 candidates | unowned |

Item 0 was not in the original scope; it was found by running the gates. Item 5 was
attempted, measured, and reverted in favour of item 7.

## Performance — not measured

No performance judgement was made. Hot-path candidates for a future baseline, listed as
hypotheses only:

| Candidate | Why it is a candidate |
| --- | --- |
| `BlockLayout+IncrementalLayoutPass.applyIncrementalLayout` | 119 lines, 25 branch tokens, runs per edit |
| `BlockLayout+Preparation.prepare` | 122 lines |
| `EditorSession+Rendering.makeTextSelectionPresentation` | 93 lines, runs per frame |
| `EditorSession+RenderDamage.redrawRects` | 78 lines, runs per frame |
| `TextKitPreparedLayoutStore` | 388 lines of eviction policy |
| `BlockLayout+VisibleOrderRelocation.relocateVisibleOrderSpans` | 78 lines, 17 branch tokens |

Per [ADR 0005](../ADR/0005-benchmarks-as-development-targets.md), any improvement claim
requires a `SlopadUIBenchmarkApp` baseline at 100 / 1,000 / 10,000 blocks first.
