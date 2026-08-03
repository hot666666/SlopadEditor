import SlopadCoreModel

// MARK: - Text Caret Navigation Input

extension EditorSession {
    func moveHorizontally(
        direction: EditorNavigationDirection,
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
            extending: false,
            in: request
        ) {
        case .selection(let resolvedSelection, let context):
            return applyTextNavigationSelection(
                resolvedSelection,
                context: context,
                extending: false,
                request: request
            )

        case .boundary(let logicalBoundary):
            guard case .caret = activeEditorSelection else { return nil }
            textNavigationRuntimeContext = nil
            return moveAcrossTextBoundaryIfNeeded(
                logicalBoundary: logicalBoundary,
                request: request
            )

        case .unchanged:
            return nil
        }
    }

    func moveToTextBoundary(_ direction: EditorNavigationDirection) -> EditorUpdate? {
        guard
            let position = activeTextPosition(),
            let block = editorModel.document.block(position.blockID),
            let offset = textBoundaryOffset(direction, in: block)
        else { return nil }

        guard position.offset != offset else { return nil }
        return handleSelectionChange(.caret(blockID: position.blockID, offset: offset))
    }

    func moveByWord(
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
            extending: false,
            in: request
        ) {
        case .selection(let resolvedSelection, let context):
            return applyTextNavigationSelection(
                resolvedSelection,
                context: context,
                extending: false,
                request: request
            )
        case .boundary, .unchanged:
            return nil
        }
    }

    func textBoundaryOffset(
        _ direction: EditorNavigationDirection,
        in block: Block
    ) -> Int? {
        switch direction {
        case .left:
            return 0
        case .right:
            if
                let composition,
                composition.blockID == block.id,
                let effectiveLength = effectiveTextLength(for: composition)
            {
                return effectiveLength
            }
            return block.content.length
        case .up, .down:
            return nil
        }
    }
}
