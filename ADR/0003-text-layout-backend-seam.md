# 0003 - Keep Text Layout Behind a Backend Seam

Date: 2026-07-08

## Status

Accepted. Amended 2026-08-08 — see "Amendment: narrow contracts, one backend".

## Context

Block height is not a fixed property. It depends on text content, available width, style,
line fragments, inline marks, and platform text shaping behavior. SlopadEditor currently proves
this path with TextKit2, but the engine is not supposed to be tied to AppKit/TextKit.

The text layout path must support more than height measurement: caret rects, selection
rects, text hit-testing, line fragment snapshots, and drawing handoff all depend on the
same block-local text layout facts.

## Decision

Keep the public text layout seam in `SlopadCoreModel/Layout` as
`BlockTextLayoutProtocol` and related value types. Keep block-local request construction
and cache policy inside `SlopadEditorBlockLayout/TextLayout`.

`SlopadEditorAppKitTextKit` is the current AppKit/TextKit2 backend. It implements the seam and
provides fragment layout, geometry, attributed-content, and drawing helpers to the
default `SlopadEditorAppKitUI` adapter. TextKit2 types do not belong in `SlopadEngine`,
`SlopadEditorModel`, or `SlopadEditorBlockLayout`.

The seam anchors a coherent geometry contract, not a height-only service or high-level
paint hook. `EditorSession` owns the live composition overlay and supplies it to
`BlockLayout`'s effective content projection. BlockLayout measurement, Session geometry
queries, and adapter drawing helpers then consume the same effective request. A complete
alternative pipeline therefore pairs a coherent backend with its own platform adapter
around `EditorSession`.

Selection inside marked text uses the same ownership rule. Effective composition offsets
live in a Session runtime selection overlay and are projected through updates, snapshots,
and active-input descriptors. `EditorModel.selection` stays in canonical document
coordinates; commit, cancel, or an implicit composition exit discards the overlay before
canonical mutation or selection replacement.

Block-local text navigation is part of that coherent contract. Physical left/right
movement, Unicode word boundaries, word deletion ranges, and pointer word selection depend
on the same shaped effective text as caret and hit-test geometry. The platform adapter
translates native selectors into direction/destination input, the backend resolves a
selection or logical block boundary, and `EditorSession` validates and applies that fact to
canonical selection or commands. The backend never mutates editor state.

`TextPosition` carries a platform-neutral upstream/downstream affinity for soft-line
boundary ambiguity. Some bidirectional runs additionally require a layout-derived inline
position to preserve physical traversal when the same logical position has more than one
visual caret. The backend returns that value as `TextNavigationContext`; `EditorSession`
keeps it only while the exact selection and effective layout request still match. It is
never canonical document or selection state. Concrete locale hints remain configuration
of the platform backend; AppKit `NSFont`, `NSColor`, `NSTextLocation`, and `Locale` values
do not enter the headless targets.

Runtime backend replacement is an atomic Session operation. Replacing the backend advances
the text-layout revision, discards cached and lazy-estimate measurements produced by the
previous backend, and marks all layout geometry dirty. A platform adapter that owns a
matching drawing backend replaces both sides from one configuration before publishing its
next surface.

## Consequences

- Do not rename `textLayouter` to `textMeasurer`; the seam covers more than height.
- A future UIKit or non-Apple backend should implement the same layout protocol instead
  of changing engine semantics.
- Layout cache invalidation belongs to `SlopadEditorBlockLayout`, not the platform backend.
- Adapting `EditorTextRenderDescriptor` to backend requests belongs to the platform UI
  adapter, so the TextKit backend does not depend on `SlopadEngine`.
- Native views draw from session render descriptors and backend layout results; they do
  not own editor selection/composition semantics.
- Engine code must not implement physical navigation as logical `offset +/- 1` or define
  Unicode words by spaces. A backend may use a documented logical fallback, while a native
  backend supplies its platform's bidi and linguistic behavior.
- Layout-derived navigation context is transient Session state. It must be discarded when
  the selection, effective request, or backend changes instead of being persisted in the
  canonical model.
- The default AppKit chrome/theme hook cannot replace backend text layout or drawing.
- Hosts do not mutate layout revision counters independently of the backend instance.


## Amendment: narrow contracts, one backend

Date: 2026-08-08 — issue #34, epic #23.

The original decision said the seam covers more than height, and warned against renaming
`textLayouter` to `textMeasurer`. That still holds: measurement, geometry, navigation, and
drawing must agree on the same shaped text, so they come from one coherent backend.

What it did not say is how *narrow* each consumer's view of that backend should be. In
practice `BlockLayout` was handed all ten methods and called exactly one:

| method | BlockLayout | EditorSession | AppKit UI |
| --- | :---: | :---: | :---: |
| `measure` | used | | |
| `textFrame` | | used | used |
| `lineFragments` | | used | used |
| `caretRect` | | used | used |
| `selectionRects` | | used | used |
| `textPosition` | | via `textHitTest` default | |
| `textHitTest` | | used | |
| `navigate` | | used | |
| `wordRange` | | used | |
| `deletionRange` | | used | |

Handing a layer that owns derived geometry the ability to ask about word boundaries invites
it to start answering questions about text meaning, which is the boundary this ADR exists to
protect. `EditorSession` uses everything except `measure`, `selectionRects`, and
`textPosition`; it is typed to exclude measurement for the same reason, since measuring
outside `BlockLayout` would bypass that layer's cache.

`BlockTextLayoutProtocol` is therefore split into `BlockMeasuring`,
`TextGeometryResolving`, `TextNavigationResolving`, and `TextDeletionResolving`, with
`BlockTextLayoutProtocol` refining all four. A backend adopts the whole seam as before;
`BlockLayout` is injected `any BlockMeasuring` only.

Consequences added by this amendment:

- Splitting the contracts is not splitting the implementation. A backend that answered
  geometry from a different layout than it measured with would violate the original
  decision, and nothing here permits that.
- `TextKitTextSystem` is the public construction boundary for the AppKit/TextKit2 backend.
  It returns a layouter and renderer backed by one hidden `TextKitLayoutContext`.
  Standalone layouter and renderer initializers are internal so a downstream adapter
  cannot accidentally assemble a split backend.
- Do not create a SwiftPM target per capability. The protocols live where the seam already
  lived, in `SlopadCoreModel/Layout`.
- Caret and selection rectangles arrive through the Session snapshot (issue #35), resolved
  in document coordinates so an adapter draws rather than asks. `EditorSession` memoizes them
  across the adapter's surface-convergence renders, which run many times per paint.
- One synchronous query stays: `EditorSession.textLineFragmentRects(in:)`, used to decide
  whether a mouse-down lands on text. Unlike the caret, its input is an ad hoc pointer
  position rather than tracked selection state, so there is no snapshot slot it could arrive
  in and no render to attach it to. It is still a Session call — the adapter does not reach
  the backend — but it is answered live.
