import SlopadCoreModel

// MARK: - Selection Transition

extension EditorSession {
    func handleActiveTextSelectionChanged(
        blockID: BlockID,
        selectedRange: TextRange
    ) -> EditorUpdate {
        if let composition, composition.blockID == blockID {
            let selection = TextSelection(
                anchor: TextPosition(blockID: blockID, offset: selectedRange.lowerBound),
                focus: TextPosition(blockID: blockID, offset: selectedRange.upperBound)
            )
            guard let normalized = normalizedCompositionSelection(selection, for: composition)
            else {
                return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
            }
            return handleCompositionSelectionChange(normalized)
        }

        guard
            let block = editorModel.document.block(blockID),
            selectedRange.lowerBound >= 0,
            selectedRange.lowerBound <= selectedRange.upperBound,
            selectedRange.upperBound <= block.content.length
        else {
            return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
        }

        if activeTextPosition()?.blockID == blockID,
            activeTextRange() == selectedRange
        {
            return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
        }

        let selection: EditorSelection
        if selectedRange.isEmpty {
            selection = .caret(blockID: blockID, offset: selectedRange.lowerBound)
        } else {
            selection = .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: selectedRange.lowerBound),
                    focus: TextPosition(blockID: blockID, offset: selectedRange.upperBound)
                )
            )
        }
        return handleSelectionChange(selection)
    }

    func handleBlockSelection(
        anchor: BlockHitTestResult,
        focus: BlockHitTestResult
    ) -> EditorUpdate {
        guard let blockSelection = blockSelection(from: anchor, to: focus) else {
            return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
        }
        return handleSelectionChange(.blocks(blockSelection))
    }

    func handleSelectionChange(_ selection: EditorSelection) -> EditorUpdate {
        let previousSelection = activeEditorSelection
        if
            let composition,
            selection.isCompatibleWithComposition(blockID: composition.blockID),
            let textSelection = textSelection(from: selection),
            let normalized = normalizedCompositionSelection(textSelection, for: composition)
        {
            return handleCompositionSelectionChange(
                normalized,
                previousSelection: previousSelection
            )
        }

        let compositionExit = commitCompositionForImplicitExitIfNeeded(compatibleWith: selection)
        editorModel.replaceSelection(selection)
        if activeEditorSelection != previousSelection {
            textNavigationRuntimeContext = nil
        }
        return makeEditorUpdate(
            invalidation: compositionExit.invalidation,
            previousSelection: previousSelection
        )
    }

    private func handleCompositionSelectionChange(
        _ selection: TextSelection,
        previousSelection: EditorSelection? = nil
    ) -> EditorUpdate {
        let previousSelection = previousSelection ?? activeEditorSelection
        let nextSelection = editorSelection(for: selection)
        guard previousSelection != nextSelection else {
            return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
        }

        compositionSelection = selection
        textNavigationRuntimeContext = nil
        return makeEditorUpdate(
            invalidation: EditorUpdateInvalidation(),
            previousSelection: previousSelection
        )
    }

    private func textSelection(from selection: EditorSelection) -> TextSelection? {
        switch selection {
        case .caret(let position):
            return TextSelection(anchor: position, focus: position)
        case .text(let selection) where selection.isSingleBlock:
            return selection
        case .inactive, .blocks, .text:
            return nil
        }
    }
}
