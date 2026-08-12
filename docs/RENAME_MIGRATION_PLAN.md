# Rename Migration Plan

Status: in progress. Stages 0-3 complete.

Target scheme: [ADR 0016](../ADR/0016-name-the-package-slopadeditor-and-reserve-slopad-for-the-app.md).
That record fixes *what* the names become; this document owns *how the tree gets there
without a broken intermediate state*.

Progress meter: `bash scripts/verify-naming.sh`.

## The Safety Property

**The tree is buildable, green, and shippable between every stage.** No stage depends on a
later stage to compile. Any stage can be the last one applied for a week without leaving the
repository in a state that a new contributor would mis-read as finished.

This is what makes a 358-file rename safe: it is never one change. It is a sequence of small
changes, each proven by the compiler and the gates, each revertable with a single
`git revert`.

Three rules hold at every stage:

1. **A module rename and the gate-script edits that name it are one commit.** Never two.
   `f059bc5` violated this and `verify-host-surface.sh` failed closed against correctly
   renamed fixtures until it was repaired. `scripts/verify-host-surface.sh` names 15 modules
   as literal strings and `scripts/verify-archive-surface.sh` names 6; a rename that misses
   them either breaks the gate or, worse, silently stops probing the symbol it was written
   to pin.
2. **A public product rename and its downstream fixture updates are one commit.** The
   fixtures exist to fail when the host contract moves. They must move with it.
3. **"Done" is measured, not eyeballed.** `verify-naming.sh` reports what remains, by stage
   category. A stage is complete when its category reaches zero, not when the diff looks
   plausible.

## Baseline

Measured on the branch that carries this document:

```
1379 occurrences in 358 files

   400 in 150 file(s)  test
   318 in 147 file(s)  module source
   265 in  12 file(s)  doc + prose
   117 in   3 file(s)  HTML page
   112 in  14 file(s)  ADR
    56 in   6 file(s)  script + gate
    47 in  10 file(s)  development target
    34 in   9 file(s)  downstream fixture
    30 in   7 file(s)  repo tooling
```

## The Per-Module Recipe

Every module stage runs the same steps. Deviating from the order is how a step gets skipped.

1. `git mv Sources/<Old> Sources/<New>` — keeps file history.
2. `Package.swift`: the target name, every `dependencies:` reference to it, and its
   `products:` entry when it has one.
3. Every `import <Old>` across `Sources/`, `Tests/`, `Debug/`, `Benchmarks/`, `Fixtures/`,
   and the `<Old>Tests` target and directory. A test target whose name no longer matches its
   module does not build, so it moves in the same stage rather than waiting.
4. **`scripts/verify-host-surface.sh` and `scripts/verify-archive-surface.sh`** — allowlists,
   negative probes, and any literal manifest assertion. Watch for shell ANSI-C strings of the
   form `$'AppKit\nSlopadX\nSwiftUI'`: the literal backslash-n puts a word character
   immediately before the module name, so a word-boundary search does not find it. Stage 3
   shipped a stale allowlist this way and the gate caught it.
5. `Fixtures/*/Package.swift` and fixture sources, when the module is a product.
6. Any type inside the module that shares its name — `SlopadArchive`, `SlopadMarkdown`, and
   the `SlopadSwiftUI` facade types are namespace enums and structs whose names must track
   their module.
7. Documents that name the module: `docs/ARCHITECTURE.md`, the relevant ADRs, `README.md`.
8. `rm -rf Fixtures/*/.build` — each fixture caches a resolved manifest that still points
   at the old `Sources/<Old>` path, and SwiftPM reports it as `missing inputs` rather than
   re-resolving. Found while running stage 2.
9. Gates, in this order:
   ```sh
   swift build --quiet
   swift test --quiet
   bash scripts/verify-host-surface.sh
   bash scripts/verify-archive-surface.sh
   git diff --check
   bash scripts/verify-naming.sh          # the module's name is gone
   ```
   Add the product builds and fixture builds from [Testing](TESTING.md) whenever the stage
   touches a public product.
10. One commit. `git revert` restores a green tree.

## Stages

Module stages run in ascending fan-in so the recipe is proven on the smallest blast radius
first and the 239-file rename happens last, when the procedure is routine.

| # | Stage | Moves | Blast radius | Notes |
| --- | --- | --- | --- | --- |
| 0 | Guard and decision | ADR 0016, this plan, `verify-naming.sh` | 3 new files | **Complete.** No rename yet. |
| 1 | Prose and window titles | project name in prose; `Slopad Debug` → `SlopadEditor Debug` | ~28 prose sites, 5 strings | No identity change; zero build risk. Establishes vocabulary before modules move. |
| 2 | `SlopadDataStructure` | → `SlopadEditorDataStructure` | 1 import, 14 files | **Pilot.** Internal-only, no product, no fixture. Proves the recipe including the script step. |
| 3 | `SlopadSwiftUI` | → `SlopadEditorSwiftUI` | 1 import, 15 files | First public product; first fixture update. |
| 4 | `SlopadMarkdownInputRules` | → `SlopadEditorMarkdownInputRules` | 2 imports, 7 files | Internal. |
| 5 | `SlopadArchive` | → `SlopadEditorArchive` | 2 imports, 16 files | Product; type `SlopadArchive` renames with it; `verify-archive-surface.sh`. |
| 6 | `SlopadMarkdown` | → `SlopadEditorMarkdown` | 4 imports, 19 files | Product; type `SlopadMarkdown` renames with it. |
| 7 | `SlopadAppKitUI` | → `SlopadEditorAppKitUI` | 4 imports, 43 files | Product. |
| 8 | `SlopadAppKit` | → `SlopadEditorAppKit` | 7 imports, 23 files | Product; the ordinary-host facade. |
| 9 | `SlopadAppKitTextKit` | → `SlopadEditorAppKitTextKit` | 8 imports, 28 files | Product. |
| 10 | `SlopadBlockLayout` | → `SlopadEditorBlockLayout` | 18 imports, 49 files | Internal. |
| 11 | `SlopadEditorModel` | → `SlopadEditorDocumentModel` | 27 imports, 53 files | **Not a prefix substitution.** Resolves the collision; see ADR 0016. |
| 12 | `SlopadEngine` | → `SlopadEditorEngine` | 39 imports, 107 files | Product. |
| 13 | `SlopadCoreModel` | → `SlopadEditorCoreModel` | **239 imports, 265 files** | Largest. Mechanical, compiler-proven, but run alone. |
| 14 | SwiftUI facade types | `SlopadEditor`→`SlopadEditorView`, `SlopadEditorModel`→`SlopadEditorViewModel`, `SlopadDocument`→`SlopadEditorDocument` | public API | Host-visible; fixtures and `verify-host-surface.sh` probes move together. |
| 15 | Development targets | `SlopadDebugApp`, `SlopadUIBenchmarkApp`, `SlopadHeightBenchmark`, `SlopadSessionBenchmark` | 4 targets | `justfile` and `scripts/slopad-debug-*.sh` move with them, including their filenames. |
| 16 | Repo tooling and pages | `.github/ISSUE_TEMPLATE/*`, `.codex/agents/*`, `docs/slopad-architecture-map.html` and its filename | 30 + 117 sites | The HTML pages are projections; regenerate rather than hand-edit where practical. |
| 17 | Seal | `verify-naming.sh --strict` exits 0; add it to `.github/workflows` | — | The guard becomes a gate. |

## Rollback

Each stage is one commit against a green tree, so `git revert <sha>` is the whole story.
Stages are independent in both directions: reverting stage 7 does not require reverting 8,
because module names do not reference each other — only importers reference them, and those
edits live in the same commit.

The one ordering constraint is the final seal, which cannot land before every category is zero.

## Open Decisions

These do not block stage 1 and can be answered before the stage that needs them.

- **Stage 15 · repository directory name.** SwiftPM derives a path dependency's identity from
  the directory, not from `Package.swift`. The fixtures currently resolve
  `identity: slopad` from `/…/project/Slopad`. Renaming the working copy to `SlopadEditor`
  makes identity match the package; leaving it does not break anything, since fixtures use
  `path: "../.."`. Decide before sealing so `Package.resolved` churn happens once.
- **Stage 16 · handoff document.** `Slopad_Semantic_Editor_Architecture_Handoff.md` is 2,227
  lines with 13 references to a still-earlier name (`BlockEditorKit`) and 5 broken relative
  links. `AGENTS.md` calls it a background record, not a work order. Renaming it in place,
  archiving it, or deleting it are all defensible; it is currently on `verify-naming.sh`'s
  allowlist so it cannot block the seal.
- **Stage 14 · `SlopadEditorDocument`.** The SwiftUI `SlopadDocument` and the archive's
  document vocabulary both want this name. Confirm no collision at stage 14 rather than
  assuming one.
