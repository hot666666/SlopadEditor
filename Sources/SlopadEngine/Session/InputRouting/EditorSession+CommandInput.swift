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

        case .enter:
            return handleEnterInputCommand()

        case .shiftEnter:
            guard canRouteTextCommand() else { return nil }
            return handleCommand(.handleShiftEnter)

        case .escape:
            return handleEscapeInputCommand()

        case .clearSelection:
            return handleClearSelectionInputCommand()

        case .navigate(let navigation):
            return handleNavigationCommand(navigation)

        case .indent:
            return handleIndentInputCommand()

        case .outdent:
            return handleOutdentInputCommand()

        case .toggleInlineStyle(let style):
            switch inlineStyleTarget() {
            case .range(let blockID, let range):
                return handleCommand(
                    .toggleTextStyle(blockID: blockID, range: range, style: style))
            case .caret:
                return handleCommand(.toggleStoredStyle(style))
            case .none:
                return nil
            }

        case .clearInlineStyles:
            switch inlineStyleTarget() {
            case .range(let blockID, let range):
                return handleCommand(.clearTextStyles(blockID: blockID, range: range))
            case .caret:
                return handleCommand(.clearStoredStyles)
            case .none:
                return nil
            }

        case .moveToTextStart:
            guard canRouteTextCommand() else { return nil }
            return moveToTextBoundary(.left)

        case .moveToTextEnd:
            guard canRouteTextCommand() else { return nil }
            return moveToTextBoundary(.right)

        case .extendToTextStart:
            guard canRouteTextCommand() else { return nil }
            return extendTextSelection(to: .left)

        case .extendToTextEnd:
            guard canRouteTextCommand() else { return nil }
            return extendTextSelection(to: .right)

        case .selectAll:
            return handleSelectAllInputCommand()

        case .undo:
            return handleUndoInputCommand()

        case .redo:
            return handleRedoInputCommand()
        }
    }


    private func handleNavigationCommand(
        _ command: EditorInputEvent.Command.Navigation
    ) -> EditorUpdate? {
        switch command {
        case .deleteWordBackward(let viewport):
            guard canRouteTextCommand() else { return nil }
            return deleteBackwardToPreviousWordBoundary(viewport: viewport)

        case .moveLeft(let viewport):
            guard canRouteTextCommand() else { return nil }
            return moveHorizontally(direction: .left, viewport: viewport)

        case .moveRight(let viewport):
            guard canRouteTextCommand() else { return nil }
            return moveHorizontally(direction: .right, viewport: viewport)

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
        }
    }

    /// What an inline style command should act on.
    ///
    /// A selected range is styled directly. A caret has nothing to style yet, so the style is
    /// armed for whatever gets typed next instead of being dropped.
    ///
    /// Live composition yields `nil`: marking text that the input method may still replace
    /// would attach marks to characters that are about to disappear.
    private enum InlineStyleTarget {
        case range(blockID: BlockID, range: TextRange)
        case caret
    }

    private func inlineStyleTarget() -> InlineStyleTarget? {
        guard composition == nil, canRouteTextCommand() else { return nil }
        guard let selection = activeTextSelection() else { return nil }
        guard !selection.range.isEmpty else { return .caret }
        return .range(blockID: selection.position.blockID, range: selection.range)
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

    /// Drops selection in one step, from whichever mode it is in.
    ///
    /// Escape escalates one level per press, so reaching `inactive` through it requires
    /// knowing the current mode and the escalation order. This is the same transition
    /// stated once, which also keeps the implicit composition commit on it.
    private func handleClearSelectionInputCommand() -> EditorUpdate? {
        switch editorModel.selection {
        case .caret, .text, .blocks:
            return handleSelectionChange(.inactive)

        case .inactive:
            return nil
        }
    }
}
