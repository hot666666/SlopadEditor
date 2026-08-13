import SlopadEditorBlockLayout
import SlopadEditorCoreModel

// MARK: - Block Selection Navigation Input

extension EditorSession {
    func moveBlockSelection(_ movement: EditorNavigationDirection)
        -> EditorUpdate?
    {
        guard let visibleOrderOffset = movement.verticalStep else { return nil }
        guard case .blocks(let selection) = editorModel.selection else { return nil }
        guard
            let nextSelection = blockLayout.movedBlockSelection(
                selection,
                by: visibleOrderOffset,
                document: editorModel.document
            )
        else { return nil }
        return handleSelectionChange(.blocks(nextSelection))
    }

    func extendBlockSelection(_ movement: EditorNavigationDirection)
        -> EditorUpdate?
    {
        guard let visibleOrderOffset = movement.verticalStep else { return nil }
        guard case .blocks(let selection) = editorModel.selection else { return nil }
        guard
            let nextSelection = blockLayout.extendedBlockSelection(
                selection,
                by: visibleOrderOffset,
                document: editorModel.document
            )
        else { return nil }
        return handleSelectionChange(.blocks(nextSelection))
    }

}
