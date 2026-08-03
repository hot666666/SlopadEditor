# 0002 - Keep the SwiftPM Target Graph as the Architecture Boundary

Date: 2026-07-08

## Status

Accepted

## Context

The source tree used to carry broad internal coupling because editor semantics, layout
projection, public vocabulary, data structures, TextKit implementation, and demo code
were not enforced by the compiler as separate modules.

The production dependency graph is:

```mermaid
flowchart TB
    subgraph Platform["Platform Layer - macOS"]
        AppKitUI["SlopadAppKitUI"]
        AppKitTextKit["SlopadAppKitTextKit"]
    end

    subgraph Headless["Headless Engine"]
        Engine["SlopadEngine / EditorSession"]
        EditorModel["SlopadEditorModel"]
        BlockLayout["SlopadBlockLayout"]
    end

    subgraph Foundation["Foundation & Data"]
        CoreModel["SlopadCoreModel"]
        DataStructure["SlopadDataStructure"]
    end

    AppKitUI --> Engine
    AppKitUI --> AppKitTextKit
    Engine --> CoreModel
    Engine --> EditorModel
    Engine --> BlockLayout
    EditorModel --> CoreModel
    BlockLayout --> CoreModel
    BlockLayout --> DataStructure
    AppKitTextKit --> CoreModel
```

Arrows show direct SwiftPM target dependencies. Debug apps, benchmarks, tests, and the
downstream fixture consume this graph from its outer edge; they do not define production
ownership.

## Decision

Keep the SwiftPM targets aligned to ownership:

- `SlopadCoreModel`: public vocabulary, backend seam values, package canonical document
  values.
- `SlopadEditorModel`: semantic document/selection/command/history owner.
- `SlopadBlockLayout`: layout projection, visible order, invalidation, geometry, text
  measurement cache, height index owner.
- `SlopadDataStructure`: pure data structures with no editor vocabulary.
- `SlopadEngine`: public `EditorSession` facade and orchestration.
- `SlopadAppKitTextKit`: AppKit/TextKit2 text layout/rendering backend.
- `SlopadAppKitUI`: reusable AppKit view/controller adapter.
- `SlopadDebugApp`: AppKit reference/debug host.
- `SlopadUIBenchmarkApp`: AppKit UI benchmark harness.

Use Swift `package` access for cross-target internal interfaces. Use `public` only for
host-facing Session contracts, public vocabulary, backend seam values, and intentional
platform host surfaces such as the AppKit controller, style, and chrome contract.

## Consequences

- `SlopadEditorModel` must not import `SlopadBlockLayout`.
- `SlopadBlockLayout` must not import `SlopadEditorModel`.
- `SlopadEngine` may compose both owners and translate between semantic change facts and
  layout invalidation facts.
- `SlopadAppKitTextKit` implements the CoreModel backend seam and must not depend on
  `SlopadEngine`; adapting Session render descriptors to TextKit calls belongs to
  `SlopadAppKitUI`.
- A complete platform replacement adds a sibling adapter that depends on `SlopadEngine`
  and a coherent backend. It does not add platform dependencies to the engine or turn the
  default AppKit chrome hook into a renderer seam.
- `SlopadCoreModel` is not a shared helper bucket. A value belongs there only when it is
  public vocabulary, a backend seam value, or package canonical document state.
- Any new public/package surface needs producer, consumer, invariant, and dependency
  direction evidence.
