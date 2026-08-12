# 0012 - Decide the host embedding surface by a three-part test

Date: 2026-08-03

## Status

Accepted

## Context

The public surface was shaped around `Fixtures/DownstreamAppKitHost`, which mounts the
editor as a window's entire content. That fixture is a strong gate but it was the only one,
and it cannot see the friction of embedding the editor as one subview of a larger app.

Five things a host needed were reachable only by re-deriving them, and each failed
silently rather than loudly:

| Concern | What the engine already knew | Why a host could not derive it |
| --- | --- | --- |
| Reload suppression | Committed versus other updates | A declarative host re-evaluates its body constantly; without an identity rule every pass looks like a document replacement and takes the caret, undo stack, and live IME composition with it |
| Session staleness | The per-Session epoch | `resetDocument` restarts `EditorDocumentRevision` at zero, so a held revision cannot be attributed to a Session |
| Focus | First responder state | There was no focus/blur action, no query, and no change notification; `renderAndSyncSurface(makeFirstResponder:)` — a render call — stood in for a focus contract |
| Unconsumed input | Whether a command was consumed | `handleEscapeInputCommand` escalates caret → blocks → inactive and then returns `nil` without publishing an update |
| Content height | `totalHeight` | Readable only by subscribing to `onSnapshotChanged`, which fires on every scroll and render pass |

Individually small. Together they meant every embedding host rewrote the same lifecycle
code, and got it wrong in ways that surface as lost edits, a lost final IME syllable, or a
reset caret — never as a crash or a compile error.

The risk in fixing this is the one already recorded in `docs/ROADMAP.md`: *"If the AppKit
facade or UI adapter accumulates too many convenience features, platform code can start
owning engine semantics again."* "A host would find this convenient" is not a sufficient
reason to make something public.

## Decision

### The exposure test

A capability joins the public host surface only when **all three** hold:

1. **A host cannot implement it correctly without engine-internal knowledge.** Session
   epoch, the committed/uncommitted distinction, and composition state all qualify. A value
   a host can compute from what it already has does not.
2. **Getting it wrong causes silent data or input loss, not inconvenience.** Lost edits, a
   dropped IME syllable, a destroyed undo stack, stolen focus. An awkward-but-correct
   workaround fails this test.
3. **It is expressible as a synchronized action or a value observation.** Never as a policy
   hook over native key, IME, pointer, reveal, or paint pipelines — those stay
   adapter-owned.

Failing any one excludes it. Test 3 is the guardrail against test 2 being argued
expansively: `onUnhandledAction` reports what the engine already decided and cannot change
that decision, which is what keeps it a notification rather than a hook.

### What the test admitted

- `EditorSessionEpoch`, carried on `EditorDocumentSnapshot` and `EditorUpdate`.
- `setFocused(_:)`, `isFocused`, `onFocusChange`.
- `onUnhandledAction`.
- `AppKitEditorAction.clearSelection` and `SlopadEditorDocumentModel.clearSelection()`. Escape
  escalates one level per press, so "no selection" through it requires knowing both the
  current selection mode and the escalation order (test 1), and the escape emulation a host
  writes instead takes the responder back on the ordinary action path — stolen focus while
  the user is typing somewhere else (test 2). It is one synchronized action that changes no
  engine decision (test 3). What remains selected after focus moves away stays host policy;
  the editor reports focus and offers the transition, it does not pick one.
- `contentHeight`, `onContentHeightChange`.
- `SlopadEditorSwiftUI`: `SlopadEditorView`, `SlopadEditorViewModel`, `SlopadEditorDocument`.

### What the test excluded

- **Format codecs.** A codec is not an ordinary AppKit/SwiftUI lifecycle operation, so it
  does not widen either facade. `SlopadEditorMarkdown` is the existing opt-in whole-document
  codec. [ADR 0015](0015-version-native-archive-and-keep-storage-host-owned.md) defines
  `SlopadEditorArchive` as another opt-in, pure codec with an internal target dependency only on
  `SlopadCoreModel`; its public facade exposes exactly five type-identical aliases for the
  archive graph, not a `SlopadCoreModel` product or blanket re-export. It has no Session,
  AppKit, storage, or lifecycle owner. A host still owns when to call either codec and all
  file/DB/cloud/autosave/conflict/retry/error policy. The archive product is decided but not
  yet implemented; [issue #78](https://github.com/hot666666/SlopadEditor/issues/78) tracks that
  implementation.
- **Host-owned scrolling.** A genuine second layout mode changes viewport ownership, which
  is engine-adjacent. Documented instead; remains a roadmap item.
- **Continuous caret navigation in `onUnhandledAction`.** "Move up at the first line" is a
  routine boundary hit during ordinary editing, not an escalation. Reporting it would bury
  the signal the callback carries.
- **UIKit adapter, structured paste, collapsed subtree, toolbar/slash surfaces.** Product
  features, not boundary gaps.

### The document input invariant

`[EditorBlockInput]` is the only document representation crossing the public ordinary-host
boundary. No `String`, storage format, or codec type appears in that surface. An opt-in
format target may transform core block values outside the facade: `SlopadEditorMarkdown` does so
for whole-document Markdown, and ADR 0015's `SlopadEditorArchive` will do so for the versioned
native archive after its implementation. Neither changes who owns storage.

This keeps SlopadEditor from acquiring a second canonical model by way of a convenience format.
The archive contract is deliberately narrower than `EditorDocumentSnapshot`: version plus
canonical blocks only. It excludes selection, undo/history, operation journal,
epoch/revision, composition, layout, viewport, and TextKit state.

### One continuous gate, two ordinary hosts

`Fixtures/DownstreamSwiftUIHost` is the intended companion to
`Fixtures/DownstreamAppKitHost`. [Issue #69](https://github.com/hot666666/SlopadEditor/issues/69)
established `bash scripts/verify-host-surface.sh` as their canonical continuous ADR 0012
gate; CI runs that command on every pull request. Each host builds with one product dependency, no
`@testable`, and no package-only state, so a capability that stops being public breaks at
the downstream boundary rather than being discovered by whoever integrates next. A fixture
that compiles while avoiding the difficult path is not a gate, so each executable performs
the full mount → edit → observe → flush → replace → unmount sequence and fails fast on a
contract mismatch.

Those ordinary lifecycle fixtures are not format fixtures. `DownstreamMarkdownHost` is a
separate opt-in format-consumer gate. When `SlopadEditorArchive` exists, issue #78 adds two
separate archive probes: a codec-surface target/source depending on the archive product and
importing only Foundation plus `SlopadEditorArchive`, and a lifecycle target/source that may add
exactly one public UI facade and passes its type-identical `snapshot.blocks` directly to the
codec. Neither imports raw Engine/CoreModel or package-only types. If one fixture package
contains both, they remain distinct targets/sources with distinct dependency and import
audits. Neither archive probe changes the ordinary one-product lifecycle gates, and no
fixture gains a format dependency merely to persist.

`SlopadEditorSwiftUI` is layered on `SlopadEditorAppKit` as its own target rather than folded into it,
for the same reason `SlopadEditorAppKit` is a curated umbrella and not a runtime owner. It does
not re-export `AppKitEditorViewController`: a SwiftUI host that can reach the controller
can bypass the lifecycle wiring the target exists to provide.

## Consequences

`renderAndSyncSurface` becomes `package`. It was never a focus API; it was the only thing
available. The same reasoning already removed raw `EditorInputEvent` and `currentViewport`
from the public controller surface.

`EditorDocumentSnapshot` drops `Codable`, which nothing used. Retaining it would have
forced `EditorSessionEpoch` to be decodable, letting a host manufacture an epoch and
defeating the staleness check the type exists for. A host reads its `blocks` and may pass
them to an opt-in format codec, but the host—not the codec—persists the resulting bytes and
owns their lifecycle.

`EditorSessionEpoch` stays separate from `EditorDocumentSource` (ADR 0011) rather than
reusing it. That token additionally pins revision and selection because a patch must not
land on a document the caller no longer sees, and it is unreadable during composition.
Persistence needs neither property and needs to work *during* composition — precisely when
the final syllable is at risk. Widening `EditorDocumentSource` to serve both would make
patches accept stale input.

A future request to widen the host surface is answered against the three-part test, not
against how convenient the addition would be.
