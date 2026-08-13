import SlopadEditorBlockLayout
import SlopadEditorCoreModel

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
        if editorModel.document.block(position.blockID)?.content.length == 0 {
            textSelectionDragAnchor = nil
            textSelectionPendingOrigin = (position.blockID, documentPoint)
        } else {
            textSelectionDragAnchor = position
            textSelectionPendingOrigin = nil
        }
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
        viewport: EditorViewport
    ) -> EditorUpdate? {
        let anchor: TextPosition
        if let resolvedAnchor = textSelectionDragAnchor {
            anchor = resolvedAnchor
        } else if let pending = textSelectionPendingOrigin,
            let resolvedAnchor = pendingTextSelectionAnchor(
                from: pending,
                toward: documentPoint
            )
        {
            anchor = resolvedAnchor
            textSelectionDragAnchor = resolvedAnchor
            textSelectionPendingOrigin = nil
        } else {
            return nil
        }
        _ = preparedLayout(for: viewport)
        guard
            let focusBlockID = blockLayout.blockID(atY: documentPoint.y),
            let focusHit = textHitTest(
                in: focusBlockID,
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
        guard textSelectionDragAnchor != nil || textSelectionPendingOrigin != nil else {
            return nil
        }
        textSelectionDragAnchor = nil
        textSelectionPendingOrigin = nil
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

    private func pendingTextSelectionAnchor(
        from origin: (blockID: BlockID, documentPoint: EditorPoint),
        toward documentPoint: EditorPoint
    ) -> TextPosition? {
        if documentPoint.y < origin.documentPoint.y {
            var candidate = editorModel.document.previousDepthFirstBlockID(before: origin.blockID)
            while let blockID = candidate {
                guard let block = editorModel.document.block(blockID) else { return nil }
                if block.content.length > 0 {
                    return TextPosition(blockID: blockID, offset: block.content.length)
                }
                candidate = editorModel.document.previousDepthFirstBlockID(before: blockID)
            }
        } else if documentPoint.y > origin.documentPoint.y {
            var candidate = editorModel.document.nextDepthFirstBlockID(after: origin.blockID)
            while let blockID = candidate {
                guard let block = editorModel.document.block(blockID) else { return nil }
                if block.content.length > 0 {
                    return TextPosition(blockID: blockID, offset: 0)
                }
                candidate = editorModel.document.nextDepthFirstBlockID(after: blockID)
            }
        }
        return nil
    }

}
