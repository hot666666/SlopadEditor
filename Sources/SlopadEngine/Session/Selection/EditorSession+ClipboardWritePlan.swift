import SlopadBlockLayout
import SlopadCoreModel

// MARK: - Clipboard Write Plan

extension EditorSession {
    public func clipboardWritePlan() -> EditorClipboardWritePlan? {
        switch activeEditorSelection {
        case .text(let selection):
            return textClipboardWritePlan(selection)
        case .blocks(let selection):
            return blockClipboardWritePlan(selection)
        case .inactive, .caret:
            return nil
        }
    }

    private func textClipboardWritePlan(
        _ selection: TextSelection
    ) -> EditorClipboardWritePlan? {
        if let composition,
            selection.isSingleBlock,
            selection.anchor.blockID == composition.blockID,
            let range = selection.rangeInSingleBlock,
            let block = blockLayout.effectiveBlock(
                for: composition.blockID,
                document: editorModel.document,
                composition: composition
            )
        {
            let input = EditorBlockInput(
                id: block.id,
                kind: block.kind,
                content: clipboardContent(block.content, in: range)
            )
            return EditorClipboardWritePlan(
                payload: EditorClipboardPayload(
                    content: .textSlice(EditorClipboardTextSlice(blocks: [input]))
                ),
                plainText: plainTextLine(input)
            )
        }
        guard let span = editorModel.resolveTextSpan(selection) else { return nil }
        let included = Set(span.blockIDs)
        let blocks = span.fragments.compactMap { fragment -> EditorBlockInput? in
            guard let block = editorModel.document.block(fragment.blockID) else { return nil }
            return EditorBlockInput(
                id: block.id,
                parentID: block.parentID.flatMap { included.contains($0) ? $0 : nil },
                kind: block.kind,
                content: clipboardContent(block.content, in: fragment.range)
            )
        }
        guard blocks.count == span.fragments.count else { return nil }
        let plainText = blocks.map(plainTextLine).joined(separator: "\n")
        return EditorClipboardWritePlan(
            payload: EditorClipboardPayload(
                content: .textSlice(EditorClipboardTextSlice(blocks: blocks))
            ),
            plainText: plainText
        )
    }

    private func blockClipboardWritePlan(
        _ selection: BlockSelection
    ) -> EditorClipboardWritePlan? {
        let roots = editorModel.document.topLevelBlockIDs(selection.blockIDs)
        guard !roots.isEmpty else { return nil }
        let rootSet = Set(roots)
        let blocks = editorModel.document.editorBlockInputs.filter { input in
            editorModel.document.hasAncestorOrSelf(in: rootSet, of: input.id)
        }
        let included = Set(blocks.map(\.id))
        let normalized = blocks.map { input in
            EditorBlockInput(
                id: input.id,
                parentID: input.parentID.flatMap { included.contains($0) ? $0 : nil },
                kind: input.kind,
                content: input.content
            )
        }
        return EditorClipboardWritePlan(
            payload: EditorClipboardPayload(
                content: .blockSubtrees(EditorClipboardBlockSubtrees(blocks: normalized))
            ),
            plainText: normalized.map(plainTextLine).joined(separator: "\n")
        )
    }

    private func clipboardContent(_ content: BlockContent, in range: TextRange) -> BlockContent {
        let range = range.clamped(to: content.length)
        let marks = content.marks.compactMap { mark -> BlockContent.InlineMark? in
            let lower = max(mark.range.lowerBound, range.lowerBound)
            let upper = min(mark.range.upperBound, range.upperBound)
            guard lower < upper else { return nil }
            return BlockContent.InlineMark(
                kind: mark.kind,
                range: TextRange(lower - range.lowerBound, upper - range.lowerBound)
            )
        }
        return BlockContent(text: content.text.substring(in: range), marks: marks)
    }

    private func plainTextLine(_ input: EditorBlockInput) -> String {
        switch input.kind {
        case .paragraph, .heading, .quote, .codeBlock:
            return input.content.text
        case .unorderedListItem:
            return "• \(input.content.text)"
        case .orderedListItem(let restartNumber):
            return "\(restartNumber ?? 1). \(input.content.text)"
        case .todo(let isChecked):
            return "[\(isChecked ? "x" : " ")] \(input.content.text)"
        case .divider:
            return "---"
        }
    }
}
