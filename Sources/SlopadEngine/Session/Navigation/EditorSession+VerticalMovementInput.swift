import SlopadCoreModel

// MARK: - EditorSession VerticalMovementInput

extension EditorSession {
    func handleVerticalMovementInputCommand(
        _ movement: EditorNavigationDirection,
        extending: Bool,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard movement.verticalStep != nil else { return nil }
        switch activeEditorSelection {
        case .caret(let position):
            if extending {
                return handleSelectionChange(.blocks(BlockSelection(blockIDs: [position.blockID])))
            }
            return moveAcrossVisualLineBoundaryIfNeeded(direction: movement, viewport: viewport)

        case .text(let textSelection) where textSelection.isSingleBlock:
            if extending {
                return handleSelectionChange(
                    .blocks(BlockSelection(blockIDs: [textSelection.focus.blockID]))
                )
            }
            return moveAcrossVisualLineBoundaryIfNeeded(direction: movement, viewport: viewport)

        case .blocks:
            return extending ? extendBlockSelection(movement) : moveBlockSelection(movement)

        case .inactive, .text:
            return nil
        }
    }
}
