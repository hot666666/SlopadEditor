import SlopadEditorCoreModel

// MARK: - EditorSession ActiveTextSelection

extension EditorSession {
    package var activeTextBlockID: BlockID? {
        activeTextSelection()?.position.blockID
    }

    var activeEditorSelection: EditorSelection {
        guard composition != nil, let compositionSelection else {
            return editorModel.selection
        }
        return editorSelection(for: compositionSelection)
    }

    func activeTextSelection() -> (position: TextPosition, range: TextRange)? {
        switch activeEditorSelection {
        case .inactive:
            return nil

        case .caret(let position):
            return (position: position, range: .point(position.offset))

        case .text(let selection):
            guard
                let anchorPath = editorModel.document.blockOrderPath(for: selection.anchor.blockID),
                let focusPath = editorModel.document.blockOrderPath(for: selection.focus.blockID),
                let focusBlock = editorModel.document.block(selection.focus.blockID)
            else { return nil }
            if selection.isSingleBlock {
                guard let range = selection.rangeInSingleBlock else { return nil }
                return (position: selection.focus, range: range)
            }
            let focusIsEarlier = focusPath.lexicographicallyPrecedes(anchorPath)
            let range = focusIsEarlier
                ? TextRange(selection.focus.offset, focusBlock.content.length)
                : TextRange(0, selection.focus.offset)
            return (position: selection.focus, range: range)

        case .blocks:
            return nil
        }
    }

    func activeTextPosition() -> TextPosition? {
        activeTextSelection()?.position
    }

    func activeTextRange() -> TextRange? {
        activeTextSelection()?.range
    }

    func editorSelection(for textSelection: TextSelection) -> EditorSelection {
        if textSelection.rangeInSingleBlock?.isEmpty == true {
            return .caret(textSelection.focus)
        }
        return .text(textSelection)
    }
}
