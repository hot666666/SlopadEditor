import SlopadCoreModel

// MARK: - Text Deletion Input

extension EditorSession {
    func deleteBackwardToTextStart() -> EditorUpdate? {
        deleteBackward { _, _ in 0 }
    }

    func deleteBackwardToPreviousWordBoundary(
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard
            let selection = activeTextNavigationSelection(),
            let request = textNavigationRequest(for: selection, viewport: viewport),
            let range = textLayouter.deletionRange(
                for: selection,
                direction: .backward,
                destination: .word,
                in: request
            ),
            isValidTextDeletionRange(
                range,
                for: selection,
                direction: .backward,
                destination: .word,
                in: request
            ),
            !range.isEmpty
        else { return nil }

        if composition != nil {
            return commitCompositionAndApply(
                .deleteText(blockID: request.blockID, range: range),
                effectiveSelection: selection
            )
        }
        return handleCommand(.deleteText(blockID: request.blockID, range: range))
    }

    private func deleteBackward(
        lowerBound: (Block, Int) -> Int
    ) -> EditorUpdate? {
        if let range = activeTextRange(), !range.isEmpty,
            let position = activeTextPosition()
        {
            return handleCommand(.deleteText(blockID: position.blockID, range: range))
        }

        guard
            let position = activeTextPosition(),
            let block = editorModel.document.block(position.blockID)
        else { return nil }

        let range = TextRange(lowerBound(block, position.offset), position.offset)
        guard !range.isEmpty else { return nil }
        return handleCommand(.deleteText(blockID: position.blockID, range: range))
    }
}
