import SlopadCoreModel
import SlopadEditorModel

// MARK: - Command Input

extension EditorSession {
    func handleInputCommand(_ command: EditorInputEvent.Command) -> EditorUpdate? {
        switch command {
        case .insertText(let text):
            guard canRouteTextCommand() else { return nil }
            return handleCommand(.insertText(text))

        case .replaceText(let blockID, let range, let text):
            guard canRouteTextCommand(),
                activeTextPosition()?.blockID == blockID
            else { return nil }
            return replaceActiveTextInput(blockID: blockID, range: range, text: text)

        case .pasteText(let text):
            guard canRouteTextCommand(), !text.isEmpty else { return nil }
            return handleCommand(.insertText(text))

        case .cutSelection:
            return handleCutSelectionInputCommand()

        case .deleteBackward:
            return handleDeleteBackwardInputCommand()

        case .deleteForward:
            return handleDeleteForwardInputCommand()

        case .deleteToTextStart:
            guard canRouteTextCommand() else { return nil }
            return deleteBackwardToTextStart()

        case .deleteWordBackward(let viewport):
            guard canRouteTextCommand() else { return nil }
            return deleteBackwardToPreviousWordBoundary(viewport: viewport)

        case .enter:
            return handleEnterInputCommand()

        case .shiftEnter:
            guard canRouteTextCommand() else { return nil }
            return handleCommand(.handleShiftEnter)

        case .escape:
            return handleEscapeInputCommand()

        case .indent:
            return handleIndentInputCommand()

        case .outdent:
            return handleOutdentInputCommand()

        case .moveLeft(let viewport):
            guard canRouteTextCommand() else { return nil }
            return moveHorizontally(direction: .left, viewport: viewport)

        case .moveRight(let viewport):
            guard canRouteTextCommand() else { return nil }
            return moveHorizontally(direction: .right, viewport: viewport)

        case .moveToTextStart:
            guard canRouteTextCommand() else { return nil }
            return moveToTextBoundary(.left)

        case .moveToTextEnd:
            guard canRouteTextCommand() else { return nil }
            return moveToTextBoundary(.right)

        case .moveWordLeft(let viewport):
            guard canRouteTextCommand() else { return nil }
            return moveByWord(.left, viewport: viewport)

        case .moveWordRight(let viewport):
            guard canRouteTextCommand() else { return nil }
            return moveByWord(.right, viewport: viewport)

        case .extendCharacterLeft(let viewport):
            guard canRouteTextCommand() else { return nil }
            return extendTextSelectionByCharacter(.left, viewport: viewport)

        case .extendCharacterRight(let viewport):
            guard canRouteTextCommand() else { return nil }
            return extendTextSelectionByCharacter(.right, viewport: viewport)

        case .extendToTextStart:
            guard canRouteTextCommand() else { return nil }
            return extendTextSelection(to: .left)

        case .extendToTextEnd:
            guard canRouteTextCommand() else { return nil }
            return extendTextSelection(to: .right)

        case .extendWordLeft(let viewport):
            guard canRouteTextCommand() else { return nil }
            return extendTextSelectionByWord(.left, viewport: viewport)

        case .extendWordRight(let viewport):
            guard canRouteTextCommand() else { return nil }
            return extendTextSelectionByWord(.right, viewport: viewport)

        case .moveUp(let viewport):
            return handleVerticalMovementInputCommand(.up, extending: false, viewport: viewport)

        case .moveDown(let viewport):
            return handleVerticalMovementInputCommand(.down, extending: false, viewport: viewport)

        case .extendUp(let viewport):
            return handleVerticalMovementInputCommand(.up, extending: true, viewport: viewport)

        case .extendDown(let viewport):
            return handleVerticalMovementInputCommand(.down, extending: true, viewport: viewport)

        case .selectAll:
            return handleSelectAllInputCommand()

        case .undo:
            return handleUndoInputCommand()

        case .redo:
            return handleRedoInputCommand()
        }
    }

    func canRouteTextCommand() -> Bool {
        switch editorModel.selection {
        case .caret:
            return true
        case .text(let textSelection):
            return textSelection.isSingleBlock
        case .inactive, .blocks:
            return false
        }
    }

    private func replaceActiveTextInput(
        blockID: BlockID,
        range: TextRange,
        text: String
    ) -> EditorUpdate {
        guard !range.isEmpty || !text.isEmpty else {
            return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
        }
        return handleCommand(.replaceText(blockID: blockID, range: range, text: text))
    }

    private func handleDeleteBackwardInputCommand() -> EditorUpdate? {
        switch editorModel.selection {
        case .caret:
            return handleCommand(.handleBackspace)

        case .text(let textSelection) where textSelection.isSingleBlock:
            return handleCommand(.handleBackspace)

        case .blocks:
            return handleCommand(.deleteBlockSelection)

        case .inactive, .text:
            return nil
        }
    }

    private func handleDeleteForwardInputCommand() -> EditorUpdate? {
        guard case .blocks = editorModel.selection else { return nil }
        return handleCommand(.deleteBlockSelection)
    }

    private func handleCutSelectionInputCommand() -> EditorUpdate? {
        switch activeEditorSelection {
        case .text(let textSelection) where textSelection.isSingleBlock:
            if
                composition != nil,
                let range = textSelection.rangeInSingleBlock,
                !range.isEmpty
            {
                return commitCompositionAndApply(
                    .deleteText(blockID: textSelection.anchor.blockID, range: range),
                    effectiveSelection: textSelection
                )
            }
            return handleCommand(.handleBackspace)

        case .blocks:
            return handleCommand(.deleteBlockSelection)

        case .inactive, .caret, .text:
            return nil
        }
    }

    private func handleUndoInputCommand() -> EditorUpdate? {
        let previousSelection = editorModel.selection
        guard let change = editorModel.undo() else { return nil }
        if change.documentChanged {
            recordDocumentChange()
        }
        textNavigationRuntimeContext = nil
        blockLayout.invalidateAllMeasurements()
        return makeEditorUpdate(
            invalidation: EditorUpdateInvalidation(
                visibleSequenceChanged: true,
                layoutGeometryChanged: true
            ),
            previousSelection: previousSelection
        )
    }

    private func handleRedoInputCommand() -> EditorUpdate? {
        let previousSelection = editorModel.selection
        guard let change = editorModel.redo() else { return nil }
        if change.documentChanged {
            recordDocumentChange()
        }
        textNavigationRuntimeContext = nil
        blockLayout.invalidateAllMeasurements()
        return makeEditorUpdate(
            invalidation: EditorUpdateInvalidation(
                visibleSequenceChanged: true,
                layoutGeometryChanged: true
            ),
            previousSelection: previousSelection
        )
    }

    private func handleEnterInputCommand() -> EditorUpdate? {
        switch editorModel.selection {
        case .caret:
            return handleCommand(.handleEnter)

        case .text(let textSelection) where textSelection.isSingleBlock:
            return handleCommand(.handleEnter)

        case .blocks(let blockSelection):
            guard
                let firstID = blockSelection.blockIDs.first,
                let block = editorModel.document.block(firstID)
            else { return nil }
            return handleSelectionChange(.caret(blockID: firstID, offset: block.content.length))

        case .inactive, .text:
            return nil
        }
    }

    private func handleEscapeInputCommand() -> EditorUpdate? {
        switch editorModel.selection {
        case .caret(let position):
            return handleSelectionChange(.blocks(BlockSelection(blockIDs: [position.blockID])))

        case .text(let textSelection) where textSelection.isSingleBlock:
            return handleSelectionChange(
                .blocks(BlockSelection(blockIDs: [textSelection.focus.blockID]))
            )

        case .blocks:
            return handleSelectionChange(.inactive)

        case .inactive, .text:
            return nil
        }
    }
}
