import SlopadCoreModel

// MARK: - EditorSession TextPointerDoubleClickInput

extension EditorSession {
    func selectWordOrAllTextFromPointer(
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        clearPointerDragState()
        guard
            let position = textPosition(at: documentPoint, viewport: viewport),
            let request = textNavigationRequest(for: position, viewport: viewport)
        else {
            return nil
        }

        guard
            (0...request.text.count).contains(position.offset),
            let wordRange = textLayouter.wordRange(containing: position, in: request),
            isValidTextBackendRange(wordRange, in: request)
        else { return nil }
        let fullRange = TextRange(0, request.text.count)
        let doubleClickStateMatches =
            textDoubleClickSelection?.blockID == position.blockID
            && textDoubleClickSelection?.wordRange == wordRange
        let activeRange = activeTextRange()
        let activeBlockID = activeTextPosition()?.blockID
        let activeSelectionMatchesWord =
            activeBlockID == position.blockID && activeRange == wordRange
        let activeSelectionMatchesFullText =
            activeBlockID == position.blockID && activeRange == fullRange
        let range =
            doubleClickStateMatches || activeSelectionMatchesWord || activeSelectionMatchesFullText
            ? fullRange
            : wordRange
        textDoubleClickSelection = (blockID: position.blockID, wordRange: wordRange)

        return handleSelectionChange(
            .text(
                TextSelection(
                    anchor: TextPosition(blockID: position.blockID, offset: range.lowerBound),
                    focus: TextPosition(blockID: position.blockID, offset: range.upperBound)
                )
            )
        )
    }
}
