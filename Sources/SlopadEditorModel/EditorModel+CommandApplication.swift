import SlopadCoreModel

// MARK: - Live Transaction

/// An owner-issued handle for canonical edits that are visible immediately but become one
/// history entry only when the coordinating runtime closes the group.
package struct EditorLiveTransaction {
    fileprivate let before: EditorState
    fileprivate var after: EditorState
    fileprivate var changedBlockIDs: Set<BlockID> = []
    fileprivate var operations: [EditorOperation] = []

    fileprivate init(state: EditorState) {
        before = state
        after = state
    }
}

// MARK: - EditorModel CommandApplication

extension EditorModel {
    @discardableResult
    package func apply(_ command: EditorCommand) -> EditorCommandResult {
        apply([.command(command)])
    }

    @discardableResult
    package func apply(_ entries: [EditorTransactionEntry]) -> EditorCommandResult {
        let execution = execute(entries)
        guard let transaction = execution.transaction else { return execution.result }
        record(transaction)
        return execution.result
    }

    package func beginLiveTransaction() -> EditorLiveTransaction {
        EditorLiveTransaction(state: state)
    }

    @discardableResult
    package func apply(
        _ command: EditorCommand,
        in liveTransaction: inout EditorLiveTransaction
    ) -> EditorCommandResult {
        apply([.command(command)], in: &liveTransaction)
    }

    @discardableResult
    package func apply(
        _ entries: [EditorTransactionEntry],
        in liveTransaction: inout EditorLiveTransaction
    ) -> EditorCommandResult {
        let execution = execute(entries)
        guard let transaction = execution.transaction else { return execution.result }
        liveTransaction.after = transaction.after
        liveTransaction.changedBlockIDs.formUnion(transaction.change.changedBlockIDs)
        liveTransaction.operations.append(contentsOf: transaction.change.operations)
        return execution.result
    }

    @discardableResult
    package func commit(
        _ liveTransaction: EditorLiveTransaction
    ) -> EditorCommandOutcome? {
        let documentChanged = !liveTransaction.before.document.hasSameCanonicalContent(
            as: liveTransaction.after.document
        )
        guard
            documentChanged
                || liveTransaction.before.selection != liveTransaction.after.selection
                || liveTransaction.before.storedMarks != liveTransaction.after.storedMarks
        else { return nil }

        let transaction = EditorTransaction(
            before: liveTransaction.before,
            after: liveTransaction.after,
            change: EditorChange(
                documentChanged: documentChanged,
                changedBlockIDs: liveTransaction.changedBlockIDs,
                operations: liveTransaction.operations
            )
        )
        record(transaction)
        return EditorCommandOutcome(
            selectionBefore: transaction.selectionBefore,
            change: transaction.change
        )
    }

    private func execute(
        _ entries: [EditorTransactionEntry]
    ) -> (result: EditorCommandResult, transaction: EditorTransaction?) {
        guard !entries.isEmpty else { return (.notApplicable, nil) }
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
            guard documentChanged || beforeState.selection != selection
                || beforeState.storedMarks != state.storedMarks || !operations.isEmpty
            else {
                return (.notApplicable, nil)
            }

            let transaction = EditorTransaction(
                before: beforeState,
                after: state,
                change: EditorChange(
                    documentChanged: documentChanged,
                    changedBlockIDs: changed,
                    operations: operations
                )
            )
            assertDocumentValidInDebug()
            let outcome = EditorCommandOutcome(
                selectionBefore: transaction.selectionBefore,
                change: transaction.change
            )
            return (
                documentChanged ? .document(outcome) : .selectionOnly(outcome),
                transaction
            )
        } catch {
            state = beforeState
            assertDocumentValidInDebug()
            return (.notApplicable, nil)
        }
    }

    private func record(_ transaction: EditorTransaction) {
        undoStack.append(transaction)
        trimUndoStackToBudget()
        redoStack.removeAll()
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

        case .replaceCompositionText(let blockID, let range, let text):
            try replaceCompositionText(
                blockID: blockID,
                range: range,
                text: text,
                operations: &operations,
                changed: &changed
            )

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
