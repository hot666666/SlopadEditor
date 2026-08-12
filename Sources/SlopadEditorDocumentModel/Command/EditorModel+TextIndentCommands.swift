import SlopadCoreModel

// MARK: - Text Indent Commands

extension EditorModel {
    func indentText(
        blockID: BlockID,
        range: TextRange,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard let block = state.document.block(blockID) else { throw .abort }
        let starts = touchedLineStarts(in: block.content.text, range: range)
        guard !starts.isEmpty else { throw .abort }
        let edits = starts.map { (position: $0, deleteCount: 0, insertText: "    ") }
        try applyTextIndentEdits(
            edits,
            blockID: blockID,
            range: range,
            changed: &changed
        )
    }

    func outdentText(
        blockID: BlockID,
        range: TextRange,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard let block = state.document.block(blockID) else { throw .abort }
        let starts = touchedLineStarts(in: block.content.text, range: range)
        let edits = starts.compactMap { start -> (position: Int, deleteCount: Int, insertText: String)? in
            let count = removableIndentCount(in: block.content.text, at: start)
            guard count > 0 else { return nil }
            return (position: start, deleteCount: count, insertText: "")
        }
        guard !edits.isEmpty else { throw .abort }
        try applyTextIndentEdits(
            edits,
            blockID: blockID,
            range: range,
            changed: &changed
        )
    }
}

// MARK: - Text Indent Helpers

extension EditorModel {
    private func applyTextIndentEdits(
        _ edits: [(position: Int, deleteCount: Int, insertText: String)],
        blockID: BlockID,
        range: TextRange,
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard let block = state.document.block(blockID) else { throw .abort }
        var content = block.content
        var delta = 0
        for edit in edits {
            let position = edit.position + delta
            if edit.deleteCount > 0 {
                content.delete(TextRange(position, position + edit.deleteCount))
            }
            if !edit.insertText.isEmpty {
                content.insert(edit.insertText, at: position)
            }
            delta += edit.insertText.count - edit.deleteCount
        }
        guard content != block.content else { throw .abort }
        try requireDocumentMutationSuccess(
            state.document.replaceContent(blockID: blockID, content: content))
        state.selection = selectionAfterTextIndentEdits(
            edits,
            blockID: blockID,
            originalRange: range
        )
        changed.insert(blockID)
    }

    private func selectionAfterTextIndentEdits(
        _ edits: [(position: Int, deleteCount: Int, insertText: String)],
        blockID: BlockID,
        originalRange: TextRange
    ) -> EditorSelection {
        let lower = mapOffset(originalRange.lowerBound, through: edits)
        let upper = mapOffset(originalRange.upperBound, through: edits)
        if originalRange.isEmpty {
            return .caret(blockID: blockID, offset: lower)
        }
        return .text(
            TextSelection(
                anchor: TextPosition(blockID: blockID, offset: lower),
                focus: TextPosition(blockID: blockID, offset: upper)
            )
        )
    }

    private func mapOffset(
        _ offset: Int,
        through edits: [(position: Int, deleteCount: Int, insertText: String)]
    ) -> Int {
        var mapped = offset
        var delta = 0
        for edit in edits {
            let position = edit.position + delta
            if edit.deleteCount > 0 {
                let end = position + edit.deleteCount
                if mapped > position && mapped <= end {
                    mapped = position
                } else if mapped > end {
                    mapped -= edit.deleteCount
                }
            }
            if !edit.insertText.isEmpty, mapped >= position {
                mapped += edit.insertText.count
            }
            delta += edit.insertText.count - edit.deleteCount
        }
        return mapped
    }

    private func touchedLineStarts(in text: String, range: TextRange) -> [Int] {
        let clamped = range.clamped(to: text.count)
        let lineStarts = lineStartOffsets(in: text)
        let firstStart = lineStarts.last { $0 <= clamped.lowerBound } ?? 0
        let upper =
            clamped.isEmpty
            ? clamped.lowerBound
            : max(clamped.lowerBound, clamped.upperBound - 1)
        return lineStarts.filter { $0 >= firstStart && $0 <= upper }
    }

    private func lineStartOffsets(in text: String) -> [Int] {
        var starts = [0]
        var offset = 0
        for character in text {
            offset += 1
            if character == "\n" {
                starts.append(offset)
            }
        }
        return starts
    }

    private func removableIndentCount(in text: String, at lineStart: Int) -> Int {
        var count = 0
        var offset = lineStart
        while offset < text.count && count < 4 {
            let index = text.indexAtGraphemeOffset(offset)
            guard text[index] == " " else { break }
            count += 1
            offset += 1
        }
        return count
    }
}
