import SlopadBlockLayout
import SlopadCoreModel

// MARK: - Select All Input

extension EditorSession {
    func handleSelectAllInputCommand() -> EditorUpdate? {
        switch editorModel.selection {
        case .caret(let position):
            return selectActiveBlockTextOrEscalate(blockID: position.blockID)

        case .text(let textSelection) where textSelection.isSingleBlock:
            return selectActiveBlockTextOrEscalate(blockID: textSelection.focus.blockID)

        case .text(let textSelection):
            return selectTouchedTextSpanOrEscalate(textSelection)

        case .inactive, .blocks:
            return selectAllVisibleBlocks()
        }
    }

    private func selectTouchedTextSpanOrEscalate(_ selection: TextSelection) -> EditorUpdate? {
        guard
            let span = editorModel.resolveTextSpan(selection),
            let startBlock = editorModel.document.block(span.start.blockID),
            let endBlock = editorModel.document.block(span.end.blockID)
        else { return nil }
        let fullStart = TextPosition(blockID: span.start.blockID, offset: 0)
        let fullEnd = TextPosition(blockID: span.end.blockID, offset: endBlock.content.length)
        let isAlreadyFull = span.start.offset == 0
            && span.end.offset == endBlock.content.length
            && startBlock.id != endBlock.id
        guard !isAlreadyFull else { return selectAllVisibleBlocks() }

        let expanded = selection.anchor == span.start
            ? TextSelection(anchor: fullStart, focus: fullEnd)
            : TextSelection(anchor: fullEnd, focus: fullStart)
        return handleSelectionChange(.text(expanded))
    }

    private func selectActiveBlockTextOrEscalate(blockID: BlockID) -> EditorUpdate? {
        guard let block = editorModel.document.block(blockID) else { return nil }
        let fullRange = TextRange(0, block.content.length)
        if isActiveBlockTextFullySelected(blockID: blockID, range: fullRange) {
            return selectAllVisibleBlocks()
        }
        return handleSelectionChange(
            .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: fullRange.lowerBound),
                    focus: TextPosition(blockID: blockID, offset: fullRange.upperBound)
                )
            )
        )
    }

    private func isActiveBlockTextFullySelected(blockID: BlockID, range: TextRange) -> Bool {
        guard case .text(let selection) = editorModel.selection,
            selection.isSingleBlock,
            selection.focus.blockID == blockID
        else {
            return false
        }
        return selection.rangeInSingleBlock == range
    }

    private func selectAllVisibleBlocks() -> EditorUpdate? {
        guard
            let selection = blockLayout.allVisibleBlockSelection(document: editorModel.document)
        else { return nil }
        guard editorModel.selection != .blocks(selection) else { return nil }
        return handleSelectionChange(.blocks(selection))
    }
}
