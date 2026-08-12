import SlopadCoreModel

// MARK: - Block Pointer Input

extension EditorSession {
    func selectBlockFromPointer(
        at documentPoint: EditorPoint,
        region: BlockHitRegion,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        clearPointerDragState()
        textDoubleClickSelection = nil
        guard
            let hit = hitTest(documentPoint: documentPoint, region: region, viewport: viewport)
        else {
            return isEmptyDocumentArea(documentPoint, viewport: viewport)
                ? handlePointerEmptyArea()
                : nil
        }
        blockSelectionDragAnchor = hit
        return handleBlockSelection(anchor: hit, focus: hit)
    }

    func extendBlockSelectionFromPointer(
        at documentPoint: EditorPoint,
        region: BlockHitRegion,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard let anchor = blockSelectionDragAnchor else { return nil }
        guard
            let focus = hitTest(
                documentPoint: documentPoint,
                region: region,
                viewport: viewport
            )
        else {
            return nil
        }
        return handleBlockSelection(anchor: anchor, focus: focus)
    }

    func endBlockSelectionFromPointer() -> EditorUpdate? {
        blockSelectionDragAnchor = nil
        return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
    }

    func selectBlockRangeFromPointer(
        anchor: BlockHitTestResult,
        focus: BlockHitTestResult
    ) -> EditorUpdate? {
        blockSelectionDragAnchor = nil
        return handleBlockSelection(anchor: anchor, focus: focus)
    }
}
