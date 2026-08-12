# 0016 - Name the Package SlopadEditor and Reserve Slopad for the App

## Status

Accepted. Supersedes the naming assumed by every document written before it.

Decided: 2026-08-13

Migration is staged and incomplete while this record is young. The executable plan is
[Rename Migration Plan](../docs/RENAME_MIGRATION_PLAN.md); that document tracks progress,
this one fixes the target.

## Context

This repository is a reusable block editor. It is not the application that ships to users.
**Slopad is the name of that consuming application; this package is SlopadEditor.**

Nothing in the source said so. `f059bc5` renamed the SwiftPM package identity to
`SlopadEditor` but changed no prose, no module, and no user-visible string, so the tree now
contradicts itself:

- `README.md`, `AGENTS.md`, and `docs/ARCHITECTURE.md` each open with "Slopad is a …".
- All twelve modules carry the `Slopad` prefix.
- The debug and benchmark windows title themselves `Slopad Debug` and `Slopad UI Benchmark`.

Once the application exists, every one of those reads as if it belongs to the application
rather than to the editor it embeds.

Two names are already overloaded, and a mechanical prefix substitution would make it worse:

| Name | Meanings today |
| --- | --- |
| `SlopadEditor` | the package identity; also `SlopadSwiftUI`'s public `NSViewControllerRepresentable` |
| `SlopadEditorModel` | the module owning canonical document mutation; also `SlopadSwiftUI`'s public observable class |

Substituting `Slopad` → `SlopadEditor` would produce `SlopadEditorEditorModel`, so the
scheme must be decided rather than derived.

A third constraint comes from the gate scripts. `scripts/verify-host-surface.sh` names 15
distinct modules and `scripts/verify-archive-surface.sh` names 6, as literal strings in
allowlists and negative probes. A module rename that does not update them in the same commit
either breaks the gate or, worse, silently stops probing the symbol it was written to pin.
That exact failure already happened once: `f059bc5` left the old package name in the
script's own assertion, and the gate failed closed on the wrong signal until it was
repaired.

## Decision

**1. The package, and the product family, is `SlopadEditor`. `Slopad` alone always means the
application and never appears as a name owned by this repository.**

**2. Every module carries the `SlopadEditor` prefix.**

| Today | Target |
| --- | --- |
| `SlopadCoreModel` | `SlopadEditorCoreModel` |
| `SlopadDataStructure` | `SlopadEditorDataStructure` |
| `SlopadEditorModel` | `SlopadEditorDocumentModel` |
| `SlopadBlockLayout` | `SlopadEditorBlockLayout` |
| `SlopadEngine` | `SlopadEditorEngine` |
| `SlopadMarkdownInputRules` | `SlopadEditorMarkdownInputRules` |
| `SlopadMarkdown` | `SlopadEditorMarkdown` |
| `SlopadArchive` | `SlopadEditorArchive` |
| `SlopadAppKitTextKit` | `SlopadEditorAppKitTextKit` |
| `SlopadAppKitUI` | `SlopadEditorAppKitUI` |
| `SlopadAppKit` | `SlopadEditorAppKit` |
| `SlopadSwiftUI` | `SlopadEditorSwiftUI` |

Test targets take the module name plus `Tests`. Development executables become
`SlopadEditorDebugApp`, `SlopadEditorUIBenchmarkApp`, `SlopadEditorHeightBenchmark`, and
`SlopadEditorSessionBenchmark`.

**3. `SlopadEditorModel` becomes `SlopadEditorDocumentModel`, not `SlopadEditorEditorModel`.**
The module owns the canonical document — tree, selection, commands, transactions, history —
so `DocumentModel` states its actual responsibility, and the doubled `Editor` disappears.

**4. The `SlopadSwiftUI` public types are renamed so no host-facing type shares a name with a
module or with the package.**

| Today | Target | Why |
| --- | --- | --- |
| `SlopadEditor` | `SlopadEditorView` | a SwiftUI `View`; the bare name now belongs to the package |
| `SlopadEditorModel` | `SlopadEditorViewModel` | host-facing observable state, distinct from the canonical document module |
| `SlopadDocument` | `SlopadEditorDocument` | carries the family prefix like every other public type |

**5. Long names are accepted.** `SlopadEditorMarkdownInputRules` is 30 characters. Shortening
the family prefix to `Editor…` was rejected: Swift module names share one global namespace
with everything a host imports, and `EditorEngine` or `EditorCoreModel` is exactly the kind
of name a consuming application is likely to collide with.

**6. Renaming a module and updating the gate scripts that name it is one commit, never two.**

## Consequences

Every host that adopted the package before this record must update its imports and its
`.product(name:package:)` references. There is no compatibility shim and no deprecated
alias: the package has no released version to be compatible with, and a shim would keep the
ambiguous names alive in exactly the documents this decision exists to clean up.

`docs/ARCHITECTURE.md`, `ADR 0002`, `ADR 0006`, `ADR 0012`, and every other document that
names a module become stale the moment its module moves. They are updated per stage rather
than in one pass, so no document is left describing a module that no longer exists.

`SlopadEditorCoreModel` is imported by 239 files. That rename is large but mechanical, and
the compiler proves it: a missed import does not build.

The plan trades one large risky change for a longer series of small verified ones. Each
stage is independently revertable, and the working tree is buildable and green between
stages. The cost is a longer migration and a temporary period in which the tree contains
both naming conventions — which is why the completeness guard in
[the migration plan](../docs/RENAME_MIGRATION_PLAN.md) reports remaining work rather than
allowing "looks done" to be judged by eye.
