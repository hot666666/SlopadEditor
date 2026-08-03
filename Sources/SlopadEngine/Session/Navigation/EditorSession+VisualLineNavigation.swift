import SlopadBlockLayout
import SlopadCoreModel

// MARK: - EditorSession VisualLineNavigation

extension EditorSession {
    @discardableResult
    func moveAcrossVisualLineBoundaryIfNeeded(
        direction: EditorNavigationDirection,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard let verticalStep = direction.verticalStep else { return nil }
        guard let position = activeTextPosition() else { return nil }
        _ = preparedLayout(for: viewport)
        guard
            let currentRendered = renderedBlock(
                blockID: position.blockID,
                viewportWidth: viewport.width
            ),
            let caretRect = textLayouter.caretRect(
                for: position,
                navigationContext: activeTextNavigationSelection().flatMap {
                    textNavigationContext(
                        for: $0,
                        request: currentRendered.textRender.measureRequest
                    )
                },
                in: currentRendered.textRender.measureRequest
            )
        else {
            return nil
        }

        let currentFragments = sortedLineFragments(
            textLayouter.lineFragments(for: currentRendered.textRender.measureRequest)
        )
        guard
            let currentLineIndex = lineIndex(
                containing: position.offset,
                caretRect: caretRect,
                textLength: currentRendered.textRender.measureRequest.text.count,
                in: currentFragments
            )
        else {
            return nil
        }

        let sameBlockLineIndex = currentLineIndex + verticalStep
        let targetRendered: EditorRenderedBlock
        let targetFragment: LineFragmentSnapshot?
        if currentFragments.indices.contains(sameBlockLineIndex) {
            targetRendered = currentRendered
            targetFragment = currentFragments[sameBlockLineIndex]
        } else {
            guard
                let targetBlockID = blockLayout.visibleBlockID(
                    relativeTo: position.blockID,
                    by: verticalStep,
                    document: editorModel.document
                ),
                let rendered = renderedBlock(
                    blockID: targetBlockID,
                    viewportWidth: viewport.width
                )
            else {
                return nil
            }
            targetRendered = rendered
            let targetFragments = sortedLineFragments(
                textLayouter.lineFragments(for: rendered.textRender.measureRequest)
            )
            targetFragment = verticalStep < 0 ? targetFragments.last : targetFragments.first
        }
        guard let targetFragment else { return nil }

        let preferredDocumentX = currentRendered.frame.x + caretRect.midX
        let targetLineRect = targetFragment.rect.offsetBy(
            dx: targetRendered.frame.x,
            dy: targetRendered.frame.y
        )
        let targetDocumentX = min(
            max(preferredDocumentX, targetLineRect.minX),
            targetLineRect.maxX
        )
        let targetPoint = EditorPoint(
            x: targetDocumentX - targetRendered.frame.x,
            y: targetLineRect.midY - targetRendered.frame.y
        )
        let request = targetRendered.textRender.measureRequest
        guard
            let destinationHit = validatedTextHitTest(
                textLayouter.textHitTest(at: targetPoint, in: request),
                request: request
            )
        else { return nil }
        let destination = destinationHit.result.position
        let selection = TextSelection(anchor: destination, focus: destination)
        let update = handleSelectionChange(.caret(destination))
        recordTextNavigationContext(
            destinationHit.result.navigationContext,
            for: selection,
            request: request
        )
        return update
    }
}

// MARK: - Visual Line Helpers

extension EditorSession {
    private func sortedLineFragments(_ fragments: [LineFragmentSnapshot]) -> [LineFragmentSnapshot]
    {
        fragments.sorted {
            if $0.rect.minY == $1.rect.minY {
                return $0.rect.minX < $1.rect.minX
            }
            return $0.rect.minY < $1.rect.minY
        }
    }

    private func lineIndex(
        containing offset: Int,
        caretRect: EditorRect,
        textLength: Int,
        in fragments: [LineFragmentSnapshot]
    ) -> Int? {
        guard !fragments.isEmpty else { return nil }
        let verticalTolerance: Double = 4
        let visualCandidates = fragments.indices.filter { index in
            let rect = fragments[index].rect
            return caretRect.midY >= rect.minY - verticalTolerance
                && caretRect.midY <= rect.maxY + verticalTolerance
        }
        if let visualIndex = visualCandidates.min(by: { lhs, rhs in
            abs(fragments[lhs].rect.midY - caretRect.midY)
                < abs(fragments[rhs].rect.midY - caretRect.midY)
        }) {
            return visualIndex
        }

        if let first = fragments.first, caretRect.midY < first.rect.midY {
            return fragments.startIndex
        }
        if let last = fragments.last, caretRect.midY > last.rect.midY {
            return fragments.index(before: fragments.endIndex)
        }

        let clampedOffset = max(0, min(offset, textLength))
        if clampedOffset == textLength {
            return fragments.lastIndex { fragment in
                fragment.range.lowerBound <= clampedOffset
                    && clampedOffset <= fragment.range.upperBound
            }
        }
        return fragments.firstIndex { fragment in
            fragment.range.contains(clampedOffset)
                || (fragment.range.isEmpty && fragment.range.lowerBound == clampedOffset)
        }
    }
}
