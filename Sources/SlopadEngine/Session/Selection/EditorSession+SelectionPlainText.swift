import SlopadBlockLayout
import SlopadCoreModel

// MARK: - Selection Plain Text

extension EditorSession {
    public func selectedPlainText() -> String? {
        switch activeEditorSelection {
        case .text(let textSelection) where textSelection.isSingleBlock:
            return selectedTextPlainText(textSelection)

        case .blocks(let blockSelection):
            return selectedBlockPlainText(blockSelection)

        case .inactive, .caret, .text:
            return nil
        }
    }

    private func selectedTextPlainText(_ selection: TextSelection) -> String? {
        guard
            let range = selection.rangeInSingleBlock,
            !range.isEmpty,
            let block = blockLayout.effectiveBlock(
                for: selection.anchor.blockID,
                document: editorModel.document,
                composition: composition
            )
        else {
            return nil
        }
        return block.content.text.substring(in: range)
    }

    private func selectedBlockPlainText(_ selection: BlockSelection) -> String? {
        guard !selection.blockIDs.isEmpty else { return nil }
        return selection.blockIDs.map { blockID in
            editorModel.document.block(blockID)?.content.text ?? ""
        }.joined(separator: "\n")
    }
}
