import SlopadCoreModel

// MARK: - Text Selection Navigation Input

extension EditorSession {
    func extendTextSelection(to direction: EditorNavigationDirection) -> EditorUpdate? {
        guard
            let position = activeTextPosition(),
            let block = editorModel.document.block(position.blockID),
            let offset = textBoundaryOffset(direction, in: block)
        else { return nil }
        return extendTextSelection(blockID: position.blockID, to: offset)
    }

    func extendTextSelectionByCharacter(
        _ direction: EditorNavigationDirection,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard direction.horizontalStep != nil else { return nil }
        guard
            let selection = activeTextNavigationSelection(),
            let request = textNavigationRequest(for: selection, viewport: viewport),
            let navigationDirection = direction.textNavigationDirection
        else { return nil }

        switch textLayouter.navigate(
            selection: selection,
            context: textNavigationContext(for: selection, request: request),
            direction: navigationDirection,
            destination: .character,
            extending: true,
            in: request
        ) {
        case .selection(let resolvedSelection, let context):
            return applyTextNavigationSelection(
                resolvedSelection,
                context: context,
                extending: true,
                preservingAnchor: selection.anchor,
                request: request
            )
        case .boundary, .unchanged:
            return nil
        }
    }

    func extendTextSelectionByWord(
        _ direction: EditorNavigationDirection,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard direction.horizontalStep != nil else { return nil }
        guard
            let selection = activeTextNavigationSelection(),
            let request = textNavigationRequest(for: selection, viewport: viewport),
            let navigationDirection = direction.textNavigationDirection
        else { return nil }

        switch textLayouter.navigate(
            selection: selection,
            context: textNavigationContext(for: selection, request: request),
            direction: navigationDirection,
            destination: .word,
            extending: true,
            in: request
        ) {
        case .selection(let resolvedSelection, let context):
            return applyTextNavigationSelection(
                resolvedSelection,
                context: context,
                extending: true,
                preservingAnchor: selection.anchor,
                request: request
            )
        case .boundary, .unchanged:
            return nil
        }
    }

    private func extendTextSelection(blockID: BlockID, to offset: Int) -> EditorUpdate? {
        guard let anchor = activeTextNavigationSelection()?.anchor else { return nil }

        let focus = TextPosition(blockID: blockID, offset: offset)
        if anchor == focus {
            return handleSelectionChange(.caret(focus))
        }
        return handleSelectionChange(.text(TextSelection(anchor: anchor, focus: focus)))
    }
}
