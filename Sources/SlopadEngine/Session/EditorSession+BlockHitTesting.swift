import SlopadEditorBlockLayout
import SlopadCoreModel
import SlopadEditorModel

// MARK: - Block Hit Testing

extension EditorSession {
    public func hitTest(
        documentPoint: EditorPoint,
        region: BlockHitRegion,
        viewport: EditorViewport
    ) -> BlockHitTestResult? {
        guard documentPoint.y >= 0 else { return nil }

        _ = preparedLayout(for: viewport)
        guard let blockID = blockLayout.blockID(atY: documentPoint.y) else { return nil }
        return BlockHitTestResult(blockID: blockID, region: region)
    }

    func blockSelection(
        from anchor: BlockHitTestResult,
        to focus: BlockHitTestResult
    ) -> BlockSelection? {
        blockLayout.blockSelection(
            from: anchor.blockID,
            to: focus.blockID,
            document: editorModel.document
        )
    }
}
