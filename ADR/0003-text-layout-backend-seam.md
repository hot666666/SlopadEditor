# 0003 - Keep Text Layout Behind a Backend Seam

Date: 2026-07-08

## Status

Accepted

## Context

Block height is not a fixed property. It depends on text content, available width, style,
line fragments, inline marks, and platform text shaping behavior. Slopad currently proves
this path with TextKit2, but the engine is not supposed to be tied to AppKit/TextKit.

The text layout path must support more than height measurement: caret rects, selection
rects, text hit-testing, line fragment snapshots, and drawing handoff all depend on the
same block-local text layout facts.

## Decision

Keep the public text layout seam in `SlopadCoreModel/Layout` as
`BlockTextLayoutProtocol` and related value types. Keep block-local request construction
and cache policy inside `SlopadBlockLayout/TextLayout`.

`SlopadAppKitTextKit` is the current AppKit/TextKit2 backend. It implements the seam and
provides fragment layout, geometry, attributed-content, and drawing helpers to the
default `SlopadAppKitUI` adapter. TextKit2 types do not belong in `SlopadEngine`,
`SlopadEditorModel`, or `SlopadBlockLayout`.

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
- Layout cache invalidation belongs to `SlopadBlockLayout`, not the platform backend.
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
