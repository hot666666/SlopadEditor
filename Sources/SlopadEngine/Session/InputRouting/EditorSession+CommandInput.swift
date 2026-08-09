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
            if case .text(let selection) = editorModel.selection, !selection.isSingleBlock {
                return handleCommand(.insertText(text))
            }
            return replaceActiveTextInput(blockID: blockID, range: range, text: text)

        case .pasteText(let text):
            guard !text.isEmpty else { return nil }
            if case .blocks = editorModel.selection {
                return handleCommand(.replaceBlockSelectionWithText(text))
            }
            guard canRouteTextCommand() else { return nil }
            return handleCommand(.insertText(text))

        case .pasteStructured(let payload):
            guard payload.version == EditorClipboardPayload.currentVersion else { return nil }
            return handleTransaction([.command(.pasteStructured(payload))])

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
            switch inlineStyleTarget(styleIdentity: style.caseIdentity) {
            case .range(let blockID, let range):
                return handleCommand(
                    .toggleTextStyle(blockID: blockID, range: range, style: style))
            case .ranges(let fragments, let allCovered):
                let commands = fragments.compactMap { fragment -> EditorTransactionEntry? in
                    guard !fragment.range.isEmpty else { return nil }
                    guard let block = editorModel.document.block(fragment.blockID) else {
                        return nil
                    }
                    if !allCovered,
                        block.content.coversEntirely(style.caseIdentity, in: fragment.range)
                    {
                        return nil
                    }
                    let command: EditorCommand = allCovered
                        ? .removeTextStyle(
                            blockID: fragment.blockID,
                            range: fragment.range,
                            style: style.caseIdentity
                        )
                        : .applyTextStyle(
                            blockID: fragment.blockID,
                            range: fragment.range,
                            style: style
                        )
                    return .command(command)
                }
                return handleTransaction(commands)
            case .caret:
                return handleCommand(.toggleStoredStyle(style))
            case .none:
                return nil
            }

        case .clearInlineStyles:
            switch inlineStyleTarget() {
            case .range(let blockID, let range):
                return handleCommand(.clearTextStyles(blockID: blockID, range: range))
            case .ranges(let fragments, _):
                return handleTransaction(
                    fragments.compactMap { fragment in
                        guard
                            !fragment.range.isEmpty,
                            let block = editorModel.document.block(fragment.blockID),
                            block.content.marks.contains(where: {
                                $0.range.intersects(fragment.range)
                            })
                        else { return nil }
                        return .command(
                            .clearTextStyles(blockID: fragment.blockID, range: fragment.range)
                        )
                    }
                )
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
            if case .blocks(let selection) = editorModel.selection {
                return collapseBlockSelection(selection, direction: .left)
            }
            guard canRouteTextCommand() else { return nil }
            return moveHorizontally(direction: .left, viewport: viewport)

        case .moveRight(let viewport):
            if case .blocks(let selection) = editorModel.selection {
                return collapseBlockSelection(selection, direction: .right)
            }
            guard canRouteTextCommand() else { return nil }
            return moveHorizontally(direction: .right, viewport: viewport)

        case .moveWordLeft(let viewport):
            guard canRouteTextCommand() else { return nil }
            return moveByWord(.left, viewport: viewport)

        case .moveWordRight(let viewport):
            guard canRouteTextCommand() else { return nil }
            return moveByWord(.right, viewport: viewport)

        case .extendCharacterLeft(let viewport):
            if case .blocks = editorModel.selection { return nil }
            guard canRouteTextCommand() else { return nil }
            return extendTextSelectionByCharacter(.left, viewport: viewport)

        case .extendCharacterRight(let viewport):
            if case .blocks(let selection) = editorModel.selection {
                return enterTextSelectionFromBlocks(selection)
            }
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

    private func enterTextSelectionFromBlocks(_ selection: BlockSelection) -> EditorUpdate? {
        let selectedRoots = Set(editorModel.document.topLevelBlockIDs(selection.blockIDs))
        guard let block = editorModel.document.editorBlockInputs.first(where: {
            editorModel.document.hasAncestorOrSelf(in: selectedRoots, of: $0.id)
                && $0.content.length > 0
        }) else { return nil }
        return handleSelectionChange(
            .text(
                TextSelection(
                    anchor: TextPosition(blockID: block.id, offset: 0),
                    focus: TextPosition(blockID: block.id, offset: 1)
                )
            )
        )
    }

    private func collapseBlockSelection(
        _ selection: BlockSelection,
        direction: EditorNavigationDirection
    ) -> EditorUpdate? {
        let ordered = editorModel.document.topLevelBlockIDs(selection.blockIDs)
        let blockID: BlockID?
        switch direction {
        case .left: blockID = ordered.first
        case .right: blockID = ordered.last
        case .up, .down: blockID = nil
        }
        guard let blockID, let block = editorModel.document.block(blockID) else { return nil }
        let offset = direction == .left ? 0 : block.content.length
        return handleSelectionChange(.caret(blockID: blockID, offset: offset))
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
        case ranges(fragments: [ResolvedTextFragment], allCovered: Bool)
        case caret
    }

    private func inlineStyleTarget(
        styleIdentity: BlockContent.InlineMark.Kind.CaseIdentity? = nil
    ) -> InlineStyleTarget? {
        guard composition == nil, canRouteTextCommand() else { return nil }
        switch editorModel.selection {
        case .caret:
            return .caret

        case .text(let textSelection):
            guard let span = editorModel.resolveTextSpan(textSelection) else { return nil }
            if textSelection.isSingleBlock, let fragment = span.fragments.first {
                return fragment.range.isEmpty
                    ? .caret
                    : .range(blockID: fragment.blockID, range: fragment.range)
            }
            let nonempty = span.fragments.filter { !$0.range.isEmpty }
            guard !nonempty.isEmpty else { return nil }
            let allCovered = styleIdentity.map { identity in
                nonempty.allSatisfy { fragment in
                    editorModel.document.block(fragment.blockID)?.content.coversEntirely(
                        identity,
                        in: fragment.range
                    ) ?? false
                }
            } ?? false
            return .ranges(fragments: nonempty, allCovered: allCovered)

        case .blocks(let blockSelection):
            let rootBlockIDs = editorModel.document.topLevelBlockIDs(blockSelection.blockIDs)
            let selectedRoots = Set(rootBlockIDs)
            let fragments = editorModel.document.editorBlockInputs.compactMap { input
                -> ResolvedTextFragment? in
                guard
                    editorModel.document.hasAncestorOrSelf(in: selectedRoots, of: input.id),
                    input.content.length > 0
                else { return nil }
                return ResolvedTextFragment(
                    blockID: input.id,
                    range: TextRange(0, input.content.length)
                )
            }
            guard !fragments.isEmpty else { return nil }
            let allCovered = styleIdentity.map { identity in
                fragments.allSatisfy { fragment in
                    editorModel.document.block(fragment.blockID)?.content.coversEntirely(
                        identity,
                        in: fragment.range
                    ) ?? false
                }
            } ?? false
            return .ranges(fragments: fragments, allCovered: allCovered)

        case .inactive:
            return nil
        }
    }

    func canRouteTextCommand() -> Bool {
        switch editorModel.selection {
        case .caret:
            return true
        case .text(let textSelection):
            return editorModel.resolveTextSpan(textSelection) != nil
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

        case .text:
            return handleCommand(.handleBackspace)

        case .blocks:
            return handleCommand(.deleteBlockSelection)

        case .inactive:
            return nil
        }
    }

    private func handleDeleteForwardInputCommand() -> EditorUpdate? {
        switch editorModel.selection {
        case .text:
            return handleCommand(.handleBackspace)
        case .blocks:
            return handleCommand(.deleteBlockSelection)
        case .inactive, .caret:
            return nil
        }
    }

    private func handleCutSelectionInputCommand() -> EditorUpdate? {
        switch activeEditorSelection {
        case .text(let textSelection):
            if
                composition != nil,
                textSelection.isSingleBlock,
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

        case .inactive, .caret:
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

        case .text:
            return handleCommand(.handleEnter)

        case .blocks(let blockSelection):
            guard
                let firstID = editorModel.document.topLevelBlockIDs(blockSelection.blockIDs).first,
                let block = editorModel.document.block(firstID)
            else { return nil }
            return handleSelectionChange(.caret(blockID: firstID, offset: block.content.length))

        case .inactive:
            return nil
        }
    }

    private func handleEscapeInputCommand() -> EditorUpdate? {
        switch editorModel.selection {
        case .caret(let position):
            return handleSelectionChange(.blocks(BlockSelection(blockIDs: [position.blockID])))

        case .text(let textSelection):
            guard let span = editorModel.resolveTextSpan(textSelection) else { return nil }
            return handleSelectionChange(.blocks(BlockSelection(blockIDs: span.blockIDs)))

        case .blocks:
            return handleSelectionChange(.inactive)

        case .inactive:
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
