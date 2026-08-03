import SlopadCoreModel

// MARK: - EditorSession ActiveTextSelection

extension EditorSession {
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
                selection.isSingleBlock,
                let range = selection.rangeInSingleBlock
            else {
                return nil
            }
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
