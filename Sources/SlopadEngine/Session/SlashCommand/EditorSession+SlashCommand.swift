import SlopadCoreModel
import SlopadEditorModel

// MARK: - Slash Command Runtime

extension EditorSession {
    struct SlashCommandRuntime: Equatable {
        let blockID: BlockID
        let triggerRange: TextRange
        let queryRange: TextRange
        let query: String
        let sourceRevision: EditorDocumentRevision

        var commands: [EditorSlashCommand] {
            EditorSlashCommand.allCases.filter { $0.matches(query: query) }
        }
    }

    /// Applies the selected slash command only if the rendered query still names the current
    /// document revision. Removing the source query and converting the block are recorded as
    /// one editor-model transaction, so one undo restores the exact `/query` text.
    @discardableResult
    package func applySlashCommand(
        _ command: EditorSlashCommand,
        sourceRevision: EditorDocumentRevision
    ) -> EditorUpdate? {
        guard
            composition == nil,
            let runtime = slashCommandRuntime,
            runtime.sourceRevision == sourceRevision,
            currentDocumentRevision == sourceRevision,
            runtime.commands.contains(command)
        else {
            slashCommandRuntime = nil
            return nil
        }

        let result = editorModel.apply([
            .command(
                .deleteText(
                    blockID: runtime.blockID,
                    range: TextRange(runtime.triggerRange.lowerBound, runtime.queryRange.upperBound)
                )
            ),
            .command(.setBlockKind(blockID: runtime.blockID, kind: command.blockKind)),
        ])
        guard let outcome = result.outcome else {
            slashCommandRuntime = nil
            return nil
        }

        slashCommandRuntime = nil
        textNavigationRuntimeContext = nil
        return makeEditorUpdate(
            invalidation: markLayoutDirty(for: outcome.change),
            previousSelection: outcome.selectionBefore
        )
    }

    /// Ends the noncanonical slash interpretation without touching the document, selection,
    /// or history. AppKit uses this for Escape; a later render must not reconstruct a menu
    /// from the still-present `/query` text because only the input-rule operation may start it.
    package func dismissSlashCommand() {
        slashCommandRuntime = nil
        pendingSlashCommandTrigger = nil
    }

    /// Advances an already rule-created query after an input event. This deliberately never
    /// scans a document looking for `/`: navigation to existing text, reset, undo, and paste
    /// cannot manufacture a menu. A fresh runtime starts only from `pendingSlashCommandTrigger`,
    /// which is emitted by the concrete EditorModel input rule.
    func updateSlashCommandRuntime(after inputEvent: EditorInputEvent, update: EditorUpdate?) {
        defer { pendingSlashCommandTrigger = nil }
        // AppKit clears a possible marked-text session before every ordinary native insertion.
        // A no-op clear is not a selection transition and must not close an already-open
        // slash query. A real composition had already dismissed it when composition began.
        if case .cancelComposition = inputEvent, update?.committedDocumentRevision == nil {
            return
        }
        guard composition == nil else {
            slashCommandRuntime = nil
            return
        }

        if let trigger = pendingSlashCommandTrigger {
            // Pasted source is ordinary text, not a typed slash-command trigger.
            if case .command(.pasteText) = inputEvent {
                slashCommandRuntime = nil
                return
            }
            startSlashCommandRuntime(trigger, sourceRevision: update?.committedDocumentRevision)
            return
        }

        guard let runtime = slashCommandRuntime else { return }
        // A native text system may report the same selected range more than once. Validate
        // the exact stored trigger/query relationship instead of treating every report as a
        // move; an actual move fails that validation and dismisses the menu.
        refreshExistingSlashCommandRuntime(runtime, sourceRevision: update?.committedDocumentRevision)
    }

    private func startSlashCommandRuntime(
        _ trigger: (blockID: BlockID, triggerRange: TextRange),
        sourceRevision: EditorDocumentRevision?
    ) {
        guard
            let sourceRevision,
            case .caret(let position) = editorModel.selection,
            position.blockID == trigger.blockID,
            position.offset == trigger.triggerRange.upperBound,
            let block = editorModel.document.block(trigger.blockID),
            block.content.text == "/"
        else {
            slashCommandRuntime = nil
            return
        }
        slashCommandRuntime = SlashCommandRuntime(
            blockID: trigger.blockID,
            triggerRange: trigger.triggerRange,
            queryRange: TextRange(trigger.triggerRange.upperBound, position.offset),
            query: "",
            sourceRevision: sourceRevision
        )
    }

    private func refreshExistingSlashCommandRuntime(
        _ runtime: SlashCommandRuntime,
        sourceRevision: EditorDocumentRevision?
    ) {
        guard
            case .caret(let position) = editorModel.selection,
            position.blockID == runtime.blockID,
            position.offset >= runtime.triggerRange.upperBound,
            let block = editorModel.document.block(runtime.blockID),
            position.offset <= block.content.length,
            let slashIndex = block.content.text.index(
                block.content.text.startIndex,
                offsetBy: runtime.triggerRange.lowerBound,
                limitedBy: block.content.text.endIndex
            ),
            block.content.text[slashIndex] == "/"
        else {
            slashCommandRuntime = nil
            return
        }
        let queryStart = runtime.triggerRange.upperBound
        let query = String(
            block.content.text.dropFirst(queryStart).prefix(position.offset - queryStart)
        )
        guard
            !query.contains(where: { $0.isWhitespace || $0.isNewline })
        else {
            slashCommandRuntime = nil
            return
        }

        slashCommandRuntime = SlashCommandRuntime(
            blockID: position.blockID,
            triggerRange: runtime.triggerRange,
            queryRange: TextRange(queryStart, position.offset),
            query: query,
            sourceRevision: sourceRevision ?? runtime.sourceRevision
        )
    }

    func slashCommandPresentation(
        activeTextInput: EditorSessionActiveTextInputDescriptor?
    ) -> EditorSlashCommandPresentation? {
        guard
            let runtime = slashCommandRuntime,
            runtime.sourceRevision == currentDocumentRevision
        else {
            slashCommandRuntime = nil
            return nil
        }

        let anchor: EditorRect?
        if activeTextInput?.renderDescriptor.measureRequest.blockID == runtime.blockID {
            anchor = activeTextInput?.caretRect
        } else {
            anchor = nil
        }
        return EditorSlashCommandPresentation(
            blockID: runtime.blockID,
            triggerRange: runtime.triggerRange,
            queryRange: runtime.queryRange,
            query: runtime.query,
            sourceRevision: runtime.sourceRevision,
            anchor: anchor,
            commands: runtime.commands
        )
    }
}
