## Linked issue

Closes #

## Problem

<!-- What boundary, behavior, or regression does this PR address? -->

## Owner decision

<!-- Which layer owns the behavior after this change, and why? -->

## Changes

-

## Non-goals

-

## Testing

- [ ] Not run
- [ ] `swift test --quiet`
- [ ] `swift build --product SlopadEditorAppKitUI --quiet`
- [ ] `swift build --product SlopadEditorDebugApp --quiet`
- [ ] `swift build --product SlopadEditorUIBenchmarkApp --quiet`
- [ ] `git diff --check`
- [ ] Other:

## Review guide

<!-- Reviewers should be able to review using only this PR, the linked issue, and the diff. -->

- Check that the changed behavior stays with the owner named above.
- Check for boundary regressions, behavior regressions, and missing focused tests.
- Do not rely on chat context that is not captured in the issue or this PR.

## Checklist

- [ ] The change is focused and scoped to one responsibility.
- [ ] Tests or verification cover the changed behavior.
- [ ] Public declaration changes were reviewed against ADR 0012; every widening passes its
      three-part test and has a real downstream call site, or this PR does not widen the surface.
- [ ] Ordinary AppKit/SwiftUI fixtures still use one SlopadEditor product/import with no internal bypass.
- [ ] Documentation was updated, or no documentation change is needed.
- [ ] Dependencies are merged, or this PR is intentionally stacked and marked as blocked.
