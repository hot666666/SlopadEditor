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
        case .caret:
            return moveAcrossVisualLineBoundaryIfNeeded(
                direction: movement,
                extending: extending,
                viewport: viewport
            )

        case .text:
            return moveAcrossVisualLineBoundaryIfNeeded(
                direction: movement,
                extending: extending,
                viewport: viewport
            )

        case .blocks:
            return extending ? extendBlockSelection(movement) : moveBlockSelection(movement)

        case .inactive:
            return nil
        }
    }
}
