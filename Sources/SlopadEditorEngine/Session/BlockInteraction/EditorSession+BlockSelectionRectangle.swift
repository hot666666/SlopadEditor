import SlopadCoreModel

// MARK: - Block Selection Rectangle

extension EditorSession {
    func beginBlockSelectionRectangle(
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard canBeginBlockSelectionRectangle(at: documentPoint, viewport: viewport) else {
            return nil
        }

        clearPointerDragState()
        textDoubleClickSelection = nil
        blockSelectionRectangle = (anchor: documentPoint, current: documentPoint)
        return handleSelectionChange(.inactive)
    }

    func updateBlockSelectionRectangle(
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard let rectangle = blockSelectionRectangle else { return nil }

        blockSelectionRectangle = (anchor: rectangle.anchor, current: documentPoint)
        let selection = blockSelection(intersecting: normalizedRect(
            from: rectangle.anchor,
            to: documentPoint
        ), viewport: viewport)
        return handleSelectionChange(selection.map(EditorSelection.blocks) ?? .inactive)
    }

    func endBlockSelectionRectangle() -> EditorUpdate? {
        guard blockSelectionRectangle != nil else { return nil }
        blockSelectionRectangle = nil
        return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
    }

    func normalizedRect(from anchor: EditorPoint, to current: EditorPoint) -> EditorRect {
        let minX = min(anchor.x, current.x)
        let minY = min(anchor.y, current.y)
        return EditorRect(
            x: minX,
            y: minY,
            width: max(anchor.x, current.x) - minX,
            height: max(anchor.y, current.y) - minY
        )
    }

    private func blockSelection(
        intersecting rect: EditorRect,
        viewport: EditorViewport
    ) -> BlockSelection? {
        guard !rect.isEmpty else { return nil }

        _ = preparedLayout(for: viewport)
        return blockLayout.blockSelection(
            intersectingYRange: rect.minY..<rect.maxY,
            document: editorModel.document
        )
    }

    private func canBeginBlockSelectionRectangle(
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> Bool {
        documentPoint.y >= 0
            && documentPoint.y >= viewport.scrollY
            && documentPoint.y <= viewport.scrollY + viewport.height
            && documentPoint.x >= 0
            && documentPoint.x <= viewport.width
    }
}
