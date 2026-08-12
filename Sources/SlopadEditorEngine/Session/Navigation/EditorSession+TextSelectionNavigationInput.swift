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

        let backendSelection = selection.isSingleBlock
            ? selection
            : TextSelection(anchor: selection.focus, focus: selection.focus)

        switch textLayouter.navigate(
            selection: backendSelection,
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
        case .boundary:
            return extendAcrossCharacterBoundary(selection: selection, direction: direction)
        case .unchanged:
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

        let backendSelection = selection.isSingleBlock
            ? selection
            : TextSelection(anchor: selection.focus, focus: selection.focus)

        switch textLayouter.navigate(
            selection: backendSelection,
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
        case .boundary:
            return extendAcrossCharacterBoundary(selection: selection, direction: direction)
        case .unchanged:
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

    private func extendAcrossCharacterBoundary(
        selection: TextSelection,
        direction: EditorNavigationDirection
    ) -> EditorUpdate? {
        let destination: TextPosition?
        switch direction {
        case .right:
            destination = editorModel.document.nextDepthFirstBlockID(
                after: selection.focus.blockID
            ).map { TextPosition(blockID: $0, offset: 0) }

        case .left:
            destination = editorModel.document.previousDepthFirstBlockID(
                before: selection.focus.blockID
            ).flatMap { blockID in
                editorModel.document.block(blockID).map {
                    TextPosition(blockID: blockID, offset: $0.content.length)
                }
            }

        case .up, .down:
            destination = nil
        }
        guard let destination else { return nil }
        let next = TextSelection(anchor: selection.anchor, focus: destination)
        return handleSelectionChange(editorSelection(for: next))
    }
}
