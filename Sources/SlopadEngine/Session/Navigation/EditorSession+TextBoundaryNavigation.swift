import SlopadBlockLayout
import SlopadCoreModel

// MARK: - EditorSession TextBoundaryNavigation

extension EditorSession {
    @discardableResult
    func moveAcrossTextBoundaryIfNeeded(
        logicalBoundary: TextLogicalBoundary,
        request: BlockMeasureRequest
    ) -> EditorUpdate? {
        guard case .caret(let position) = activeEditorSelection else { return nil }
        guard position.blockID == request.blockID else { return nil }

        let blockStep: Int
        switch logicalBoundary {
        case .start:
            guard position.offset == 0 else { return nil }
            blockStep = -1
        case .end:
            guard position.offset == request.text.count else { return nil }
            blockStep = 1
        }

        guard
            let targetBlockID = blockLayout.visibleBlockID(
                relativeTo: position.blockID,
                by: blockStep,
                document: editorModel.document
            )
        else {
            return nil
        }
        guard let targetBlock = editorModel.document.block(targetBlockID) else { return nil }
        let targetOffset = logicalBoundary == .start ? targetBlock.content.length : 0
        return handleSelectionChange(.caret(blockID: targetBlockID, offset: targetOffset))
    }
}
