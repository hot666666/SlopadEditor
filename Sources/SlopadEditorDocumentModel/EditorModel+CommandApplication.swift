import SlopadEditorCoreModel

// MARK: - EditorModel CommandApplication

extension EditorModel {
    @discardableResult
    package func apply(_ command: EditorCommand) -> EditorCommandResult {
        apply([.command(command)])
    }

    @discardableResult
    package func apply(_ entries: [EditorTransactionEntry]) -> EditorCommandResult {
        guard !entries.isEmpty else { return .notApplicable }
        let beforeState = state
        var operations: [EditorOperation] = []
        var changed: Set<BlockID> = []

        do throws(EditorCommandAbort) {
            for entry in entries {
                switch entry {
                case .command(let command):
                    try perform(command, operations: &operations, changed: &changed)
                case .replaceSelection(let selection):
                    state.replaceSelection(selection)
                }
            }

            let documentChanged = !beforeState.document.hasSameCanonicalContent(as: document)
            guard
                documentChanged || beforeState.selection != selection
                    || beforeState.storedMarks != state.storedMarks || !operations.isEmpty
            else {
                return .notApplicable
            }

            let transaction = EditorTransaction(
                before: beforeState,
                after: state,
                change: EditorChange(
                    documentChanged: documentChanged,
                    canonicalStructureChanged: operations.contains {
                        $0.changesCanonicalStructure
                    },
                    changedBlockIDs: changed,
                    operations: operations
                )
            )
            undoStack.append(transaction)
            trimUndoStackToBudget()
            redoStack.removeAll()
            recordSelectionChange(from: beforeState.selection)
            recordStoredMarksChange(from: beforeState.storedMarks)
            recordCanonicalStructureChange(transaction.change.canonicalStructureChanged)
            assertDocumentValidInDebug()
            let outcome = EditorCommandOutcome(
                selectionBefore: transaction.selectionBefore,
                change: transaction.change
            )
            return documentChanged ? .document(outcome) : .selectionOnly(outcome)
        } catch {
            state = beforeState
            assertDocumentValidInDebug()
            return .notApplicable
        }
    }

    private func perform(
        _ command: EditorCommand,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        switch command {
        case .insertText(let text):
            try insertText(text, operations: &operations, changed: &changed)

        case .replaceText(let blockID, let range, let text):
            try replaceText(
                blockID: blockID, range: range, text: text, operations: &operations,
                changed: &changed)

        case .deleteText(let blockID, let range):
            try deleteText(
                blockID: blockID, range: range, operations: &operations, changed: &changed)

        case .indentText(let blockID, let range):
            try indentText(
                blockID: blockID, range: range, operations: &operations, changed: &changed)

        case .outdentText(let blockID, let range):
            try outdentText(
                blockID: blockID, range: range, operations: &operations, changed: &changed)

        case .splitBlock(let blockID, let offset):
            try splitBlock(
                blockID: blockID, offset: offset, operations: &operations, changed: &changed)

        case .mergeBlocks(let target, let source):
            try mergeBlocks(
                target: target, source: source, operations: &operations, changed: &changed)

        case .setBlockKind(let blockID, let kind):
            try setBlockKind(
                blockID: blockID, kind: kind, operations: &operations, changed: &changed)

        case .toggleStoredStyle(let style):
            guard case .caret = selection else { throw .abort }
            state.toggleStoredMark(style)

        case .clearStoredStyles:
            guard case .caret = selection, !state.storedMarks.isEmpty else { throw .abort }
            state.storedMarks = []

        case .removeTextStyle(let blockID, let range, let style):
            try removeTextStyle(
                blockID: blockID, range: range, style: style, operations: &operations,
                changed: &changed)

        case .toggleTextStyle(let blockID, let range, let style):
            try toggleTextStyle(
                blockID: blockID, range: range, style: style, operations: &operations,
                changed: &changed)

        case .applyTextStyle(let blockID, let range, let style):
            try applyTextStyle(
                blockID: blockID, range: range, style: style, operations: &operations,
                changed: &changed)

        case .clearTextStyles(let blockID, let range):
            try clearTextStyles(
                blockID: blockID, range: range, operations: &operations, changed: &changed)

        case .indentBlock(let blockSelection):
            try indent(selection: blockSelection, operations: &operations, changed: &changed)

        case .outdentBlock(let blockSelection):
            try outdent(selection: blockSelection, operations: &operations, changed: &changed)

        case .moveBlockSelection(let blockSelection, let target):
            try move(
                selection: blockSelection,
                to: target,
                operations: &operations,
                changed: &changed
            )

        case .toggleTodo(let blockID):
            try toggleTodo(blockID: blockID, operations: &operations, changed: &changed)

        case .handleEnter:
            try handleEnter(operations: &operations, changed: &changed)

        case .handleShiftEnter:
            try handleShiftEnter(operations: &operations, changed: &changed)

        case .handleBackspace:
            try handleBackspace(operations: &operations, changed: &changed)

        case .replaceBlockSelectionWithText(let text):
            try replaceBlockSelectionWithText(
                text,
                operations: &operations,
                changed: &changed
            )

        case .pasteStructured(let payload):
            try pasteStructured(
                payload,
                operations: &operations,
                changed: &changed
            )

        case .deleteBlockSelection:
            try deleteBlockSelection(operations: &operations, changed: &changed)
        }
    }
}
