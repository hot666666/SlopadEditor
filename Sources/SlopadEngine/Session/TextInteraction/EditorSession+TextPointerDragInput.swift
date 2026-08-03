import SlopadBlockLayout
import SlopadCoreModel

// MARK: - EditorSession TextPointerDragInput

extension EditorSession {
    func beginTextPointerSelection(
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard let hit = textHitTest(at: documentPoint, viewport: viewport) else {
            return nil
        }
        let position = hit.result.position
        let shouldPreserveDoubleClickSelection =
            textDoubleClickSelection?.blockID == position.blockID
            && textDoubleClickSelection?.wordRange.contains(position.offset) == true
            && selectedTextRangeContains(position)
        clearPointerDragState()
        if !shouldPreserveDoubleClickSelection {
            textDoubleClickSelection = nil
        }
        textSelectionDragAnchor = position
        let selection = TextSelection(anchor: position, focus: position)
        let update = handleSelectionChange(.caret(position))
        recordTextNavigationContext(
            hit.result.navigationContext,
            for: selection,
            request: hit.request
        )
        return update
    }

    func updateTextPointerSelection(
        at documentPoint: EditorPoint,
        viewport: EditorViewport,
        blockSelectionThreshold: Double?
    ) -> EditorUpdate? {
        guard let anchor = textSelectionDragAnchor else { return nil }
        if let update = blockSelectionFromTextDragIfNeeded(
            anchor: anchor,
            documentPoint: documentPoint,
            viewport: viewport,
            threshold: blockSelectionThreshold
        ) {
            return update
        }
        guard
            let focusHit = textHitTest(
                in: anchor.blockID,
                at: documentPoint,
                viewport: viewport
            )
        else {
            return nil
        }
        let focus = focusHit.result.position
        let selection = TextSelection(anchor: anchor, focus: focus)
        if anchor == focus {
            let update = handleSelectionChange(.caret(focus))
            recordTextNavigationContext(
                focusHit.result.navigationContext,
                for: selection,
                request: focusHit.request
            )
            return update
        }
        let update = handleSelectionChange(.text(selection))
        recordTextNavigationContext(
            focusHit.result.navigationContext,
            for: selection,
            request: focusHit.request
        )
        return update
    }

    func endTextPointerSelection() -> EditorUpdate? {
        guard textSelectionDragAnchor != nil else { return nil }
        textSelectionDragAnchor = nil
        return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
    }

    private func selectedTextRangeContains(_ position: TextPosition) -> Bool {
        guard case .text(let selection) = activeEditorSelection,
            selection.isSingleBlock,
            selection.focus.blockID == position.blockID,
            let range = selection.rangeInSingleBlock,
            !range.isEmpty
        else {
            return false
        }
        return range.contains(position.offset)
    }

    private func blockSelectionFromTextDragIfNeeded(
        anchor: TextPosition,
        documentPoint: EditorPoint,
        viewport: EditorViewport,
        threshold: Double?
    ) -> EditorUpdate? {
        guard let threshold, threshold > 0,
            let anchorBlock = renderedBlock(blockID: anchor.blockID, viewportWidth: viewport.width)
        else {
            return nil
        }

        let focusID: BlockID?
        if documentPoint.y <= anchorBlock.frame.minY - threshold {
            focusID = blockSelectionFocusID(
                in: documentPoint.y..<anchorBlock.frame.midY,
                direction: .up
            )
        } else if documentPoint.y >= anchorBlock.frame.maxY + threshold {
            focusID = blockSelectionFocusID(
                in: anchorBlock.frame.midY..<documentPoint.y,
                direction: .down
            )
        } else {
            return nil
        }

        guard let focusID,
            let selection = blockLayout.blockSelection(
                from: anchor.blockID,
                to: focusID,
                document: editorModel.document
            )
        else {
            return nil
        }

        textSelectionDragAnchor = nil
        blockSelectionDragAnchor = BlockHitTestResult(
            blockID: anchor.blockID,
            region: .body,
            textPosition: anchor
        )
        return handleSelectionChange(.blocks(selection))
    }

    private enum TextDragBlockSelectionDirection {
        case up
        case down
    }

    private func blockSelectionFocusID(
        in yRange: Range<Double>,
        direction: TextDragBlockSelectionDirection
    ) -> BlockID? {
        guard
            let selection = blockLayout.blockSelection(
                intersectingYRange: yRange,
                document: editorModel.document
            )
        else {
            return nil
        }
        switch direction {
        case .up:
            return selection.anchor
        case .down:
            return selection.focus
        }
    }
}
