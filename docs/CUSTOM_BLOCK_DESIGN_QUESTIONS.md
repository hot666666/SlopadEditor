# Custom Block, Presentation, and Automation — Open Design Questions

## What this document is

A pre-implementation proposal and a decision queue. **No section of this document is a
contract.** Current source and tests define what SlopadEditor does today;
[Architecture](ARCHITECTURE.md) and the accepted [ADRs](../ADR/README.md) define its
boundaries. Where this document names a type, that type does not exist yet.

It exists because [ADR 0017](../ADR/0017-host-custom-block-boundary.md) cannot be accepted
until the questions below are answered, and because a previous handoff for this work
described the repository as it was before the `SlopadEditor` rename and before the
accessibility work in PRs #90–#93 landed.

Scheduling: this track starts after [Epic #67](https://github.com/hot666666/SlopadEditor/issues/67)
closes. Answering these questions and drafting the amendments can proceed now; code cannot.

## Corrected current-state facts

A previous handoff for this work carried stale claims. The facts below come from current
source at the time of writing.

| Stale claim | Current source |
| --- | --- |
| Every module and file path spelled with the pre-rename package prefix | The whole target graph uses the `SlopadEditor*` family under [ADR 0016](../ADR/0016-name-the-package-slopadeditor-and-reserve-slopad-for-the-app.md); `scripts/verify-naming.sh` treats a pre-rename spelling as a regression. The SwiftUI surface files are `SlopadEditorView.swift`, `SlopadEditorViewModel.swift`, `SlopadEditorDocument.swift` |
| No supported per-instance host accessibility identifier or label | `AppKitEditorViewController.configureEditorAccessibility(identifier:label:)` (`AppKitEditorViewController.swift:399-406`) and `SlopadEditorView.editorAccessibility(identifier:label:)` (`SlopadEditorView.swift:83-90`) are public. The identity is applied to the scroll surface, which also publishes an accessibility value and posts `.valueChanged` (`AppKitEditorViewController.swift:696-699`, `:872-885`) |
| Accessibility has no shipped contract at all | What remains open is block-level semantic projection and a cycle-safe cross-process automation contract, tracked by [#94](https://github.com/hot666666/SlopadEditor/issues/94) — which is currently excluded from the downstream MVP blocker set, with experiment PR #95 discarded |
| Block chrome is the presentation extension point | It is draw-only into a clipped `CGContext` (`AppKitBlockChromeRenderer.swift:10-36`), and *Treating an Appearance Hook as a Whole Text Renderer Seam* in [Lessons Learned](LESSONS_LEARNED.md) forbids widening it |
| (Absent) | The built-in floating formatting toolbar and per-block todo checkbox already ship (`AppKitFloatingFormattingToolbar.swift`, `AppKitTodoCheckboxControl.swift`). A hover rail is an addition to that chrome, not a first chrome surface |
| (Absent) | `divider` is the shipped precedent for an atomic non-text leaf and should be the derivation base for custom-block selection, Enter/Backspace, clipboard, and tint behavior |

## Blocking decisions

Each question states the constraint that makes it hard, the real options, and a
recommendation. D1–D3 block ADR 0017; D4–D6 block implementation; D7–D9 block the
presentation and automation tracks.

### D1 — Who decides a custom block's height?

`TextLayoutCache.measured` routes **every** block, `divider` included, through
`BlockMeasuring`, which is implemented by the TextKit backend
(`TextLayoutCache.swift:83-102`). A custom block has no text.
`SlopadEditorBlockLayout` may not depend on AppKit or the host, and
[ADR 0003](../ADR/0003-text-layout-backend-seam.md) keeps measurement, geometry,
navigation, and drawing as one coherent backend contract.

| Option | Shape | Cost |
| --- | --- | --- |
| **A. Canonical declared height** | The host stores height in the payload envelope; layout reads it like a constant | Simplest; makes a presentation value canonical document state, which contradicts the ownership table and breaks under font/width changes |
| **B. Provider sizing function on the layout seam** | `BlockMeasuring` gains a non-text branch answered by a registered sizer | Keeps one measurement owner; the sizer must be platform-neutral and synchronous, so an AppKit `NSView`'s intrinsic size cannot be its source |
| **C. Runtime measured height with invalidation** | The adapter measures the host view and reports a height change to Session, which invalidates that block | Matches how derived layout already works and survives resize; needs a documented convergence rule so a view that resizes in response to its own height cannot loop |

Recommendation: **C, with a B-shaped seam.** Layout keeps asking one measurement owner; the
adapter supplies the answer for custom kinds and reports changes as invalidation, never as
canonical state. This requires stating a maximum re-measure depth per layout pass.

### D2 — How does a provider put pixels inside the canvas?

| Option | Shape | Cost |
| --- | --- | --- |
| **A. Host `NSView` subview per visible custom block** | Adapter mounts/recycles host views positioned from layout | Native controls, focus, and accessibility work for free; collides with the single scroll owner, the damage/redraw model, and view recycling during fast scroll |
| **B. Second paint hook** | Provider draws into a clipped context, like chrome | Explicitly named as a recorded failure pattern; cannot host controls at all |
| **C. Overlay layer above the canvas** | Host views live in a sibling layer synchronized to scroll | Keeps canvas drawing untouched; introduces a second surface that must track scroll and damage exactly, with visible drift as the failure mode |

Recommendation: **A**, restricted to a recycled, adapter-owned mount point with explicit
lifecycle callbacks. B is excluded by lessons learned. C trades one hard synchronization
problem for a more visible one.

### D3 — What is the focus and first-responder policy for a custom body?

The canvas is the `NSTextInputClient`. If a host view becomes first responder, IME
composition, caret, and the shipped selection model lose their input surface.

| Option | Shape | Cost |
| --- | --- | --- |
| **A. Non-focusable body** | Host views never take first responder; clicks resolve to block selection; the body is display-only | Safest and matches "atomic leaf"; a host cannot ship a text field or a control that needs the keyboard |
| **B. Explicit focus lease** | The block can request focus through a Session action, and Escape or selection change returns it | Enables real controls; every IME, undo, and selection interaction now has a second focus owner to reason about |

Recommendation: **A for the first version**, with B recorded as the known next request.
The candidate consumer — displaying an app-owned Todo — does not need the keyboard.

### D4 — How does the custom case enter `BlockKind`, and what does each switch answer?

Nine production files switch exhaustively today. Adding a case is not a mechanical fix:
each site is a boundary answer (Markdown diagnostic, archive wire shape, chrome metrics,
marker kind, layout branch, clipboard plain-text fallback, selection tint). Decide whether
the case is `BlockKind.custom(typeID:version:)` with the payload in `BlockContent`, or a
single case carrying the whole envelope. Derive selection, Enter, Backspace, and tint
behavior from `divider` rather than inventing new rules.

### D5 — What is the archive compatibility policy?

The envelope pins `formatVersion:1` and fails closed on any other value. Custom blocks
require V2. Decide: does a V1 reader reject a V2 document wholesale (current fail-closed
behavior, and the honest one), and does an encoder emit V1 for documents that contain no
custom block so existing files stay readable? Also set the payload byte budget inside the
existing admission budgets — an opaque `Data` is otherwise unbounded.

### D6 — What exactly does the patch-preservation invariant check?

ADR 0017 P5 makes preservation a canonical replacement invariant rather than a producer
convention. Decide the comparison key (identity plus `typeID` plus `version` plus payload
bytes), whether reordering an unknown block is allowed without capability, and how the host
capability is expressed on the patch — it must not become a general "skip validation" flag.

### D7 — Which layer owns hover state, and does `BlockHitRegion` grow?

`BlockHitRegion` has `body`, `dragHandle`, and `gutter`. A Notion-style rail adds an insert
affordance and a block menu, and a custom body adds a fourth destination. The ownership
table puts overlay widgets in platform runtime, which argues for AppKit-owned hover with
Session-owned hit classification. Confirm that split before either side is written.

### D8 — What are the presentation tokens, and what do they invalidate?

The visual target — no permanent gutter separator, rail affordances only beside the hovered
block, inline checkbox, quiet text-block bounds, contained callout/code backgrounds, and a
text column that stays aligned across differing block presentations — is currently recorded
only as prose here, because the source screenshot lived in an OS temporary directory and
should be assumed gone. Capture the tokens in the repository before implementation.

Alignment is geometry-affecting: it changes `TextKitEditorStyle` (aliased as
`AppKitEditorStyle`), which is applied as one atomic configuration unit and participates in
text cache identity. It therefore invalidates layout caches and requires re-running the
100/1,000/10,000-block gates in `SlopadEditorUIBenchmarkApp`.

### D9 — What makes the accessibility projection cycle-safe?

[#94](https://github.com/hot666666/SlopadEditor/issues/94) requires a cycle-safe automation
surface and rules out a second state owner, a test-only input proxy, and double editable
exposure on both canvas and scroll view. A block-level semantic projection makes this
harder, and a custom block whose accessibility subtree is owned by a host view is precisely
where the earlier XCUITest snapshot recursion appeared. Decide the projection's laziness,
its recursion bound, and whether custom bodies are exposed at all in the first version
before reopening the experiment. Repeating the previous attempt without a changed failure
signature is excluded by that issue's own acceptance criteria.

## Proposed issue decomposition

To be created only after D1–D6 close, and started only after Epic #67 closes.

| ID | Title | Owner layer | Depends on | Exit |
| --- | --- | --- | --- | --- |
| C0 | Accept ADR 0017 and amend ADR 0012/0013/0015, ROADMAP, ARCHITECTURE | docs/architecture | D1–D3 | Intent documents and source agree; no document mixes contract with proposal |
| C1 | Canonical custom block vocabulary and invariants | `SlopadEditorCoreModel`, `SlopadEditorDocumentModel` | C0, D4 | Nine switch sites answered; leaf/text-capability/budget invariants tested |
| C2 | Archive V2 with custom payload budgets | `SlopadEditorArchive` | C1, D5 | Round-trip preserves identity and payload; V1/V2 compatibility policy tested at budget boundaries |
| C3 | Markdown unsupported-custom diagnostics | `SlopadEditorMarkdown` | C1 | Encode and decode fail closed with the `typeID` named; downstream Markdown fixture proves it |
| C4 | Patch preservation invariant and host capability | `SlopadEditorDocumentModel` | C1, D6 | Unknown custom blocks survive an assistant round trip; capability path covered both ways |
| C5 | Layout measurement seam for non-text blocks | `SlopadEditorBlockLayout` | C1, D1 | Height converges without canonical presentation state; re-measure depth bounded |
| C6 | Provider mount, recycling, and hit routing | `SlopadEditorAppKitUI` | C5, D2, D3, D7 | Scroll, damage, drag, and selection stay correct with visible custom bodies |
| C7 | Unsupported placeholder and preservation fixture | fixtures | C2, C4, C6 | A downstream host proves an unregistered type survives edit, move, copy, save, reload |
| C8 | Hover rail and presentation tokens | `SlopadEditorAppKitUI`, style | D7, D8 | Rail behavior verified in `SlopadEditorDebugApp`; benchmark gates re-run and recorded |
| C9 | Block semantic projection and cycle-safe automation | `SlopadEditorAppKitUI` | C6, D9, #94 | Focused AppKit regression plus a public-host lookup path, with no snapshot recursion |

## Verification gates this track invalidates

From [Testing](TESTING.md), selected by change surface rather than by habit:

```sh
swift test --quiet
git diff --check
bash scripts/verify-host-surface.sh
bash scripts/verify-archive-surface.sh
swift package dump-package
```

Plus, per owner: `SlopadEditorDebugApp` for rail, hit routing, focus, and custom-body
interaction; `SlopadEditorUIBenchmarkApp` at 100/1,000/10,000 blocks for any style,
measurement, or mount change; the downstream Markdown and archive fixtures for their own
format boundaries. Compile-only proof is not behavioral proof, and none of these substitute
for the accessibility evidence #94 requires.

## Out of scope

AI-response block kind, database-row block, date/status-picker block, custom containers
with child editor blocks, a global or dynamic provider registry, format plugin registry,
and host-owned text rendering. Image and table remain built-in canonical work under
[#50](https://github.com/hot666666/SlopadEditor/issues/50), not custom-block payloads.
