import SlopadEditorCoreModel
import SlopadEditorDocumentModel

// MARK: - EditorSession IndentInput

extension EditorSession {
    func handleIndentInputCommand() -> EditorUpdate? {
        handleIndentationInput(
            textCommand: { blockID, selectedRange in
                .indentText(blockID: blockID, range: selectedRange)
            },
            blockCommand: { blockSelection in
                .indentBlock(blockSelection)
            }
        )
    }

    func handleOutdentInputCommand() -> EditorUpdate? {
        handleIndentationInput(
            textCommand: { blockID, selectedRange in
                .outdentText(blockID: blockID, range: selectedRange)
            },
            blockCommand: { blockSelection in
                .outdentBlock(blockSelection)
            }
        )
    }

    private func handleIndentationInput(
        textCommand: (BlockID, TextRange) -> EditorCommand,
        blockCommand: (BlockSelection) -> EditorCommand
    ) -> EditorUpdate? {
        switch editorModel.selection {
        case .caret:
            guard
                canRouteTextCommand(),
                let activeSelection = activeTextSelection()
            else { return nil }
            return handleCommand(
                textCommand(activeSelection.position.blockID, activeSelection.range)
            )

        case .text(let textSelection):
            if textSelection.isSingleBlock {
                guard let range = textSelection.rangeInSingleBlock else { return nil }
                return handleCommand(textCommand(textSelection.anchor.blockID, range))
            }
            guard let span = editorModel.resolveTextSpan(textSelection) else { return nil }
            return handleTransaction([
                .command(blockCommand(BlockSelection(blockIDs: span.blockIDs))),
                .replaceSelection(.text(textSelection)),
            ])

        case .blocks(let blockSelection):
            return handleCommand(blockCommand(blockSelection))
        case .inactive:
            return nil
        }
    }
}
