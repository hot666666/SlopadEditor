import SlopadCoreModel

// MARK: - EditorModel CommandApplication

extension EditorModel {
    @discardableResult
    package func apply(
        _ command: EditorCommand
    ) -> (selectionBefore: EditorSelection, change: EditorChange)? {
        apply([.command(command)])
    }

    @discardableResult
    package func apply(
        _ steps: [EditorTransactionStep]
    ) -> (selectionBefore: EditorSelection, change: EditorChange)? {
        guard !steps.isEmpty else { return nil }
        let beforeDocument = document
        let beforeSelection = selection
        var operations: [EditorOperation] = []
        var changed: Set<BlockID> = []

        do throws(EditorCommandAbort) {
            for step in steps {
                switch step {
                case .command(let command):
                    try perform(command, operations: &operations, changed: &changed)
                case .replaceSelection(let selection):
                    self.selection = selection
                }
            }

            let documentChanged = !beforeDocument.hasSameCanonicalContent(as: document)
            guard documentChanged || beforeSelection != selection || !operations.isEmpty
            else {
                return nil
            }

            let transaction = EditorTransaction(
                beforeSnapshot: beforeDocument,
                afterSnapshot: document,
                selectionBefore: beforeSelection,
                selectionAfter: selection,
                change: EditorChange(
                    documentChanged: documentChanged,
                    changedBlockIDs: changed,
                    operations: operations
                )
            )
            undoStack.append(transaction)
            trimUndoStackToBudget()
            redoStack.removeAll()
            assertDocumentValidInDebug()
            return (
                selectionBefore: transaction.selectionBefore,
                change: transaction.change
            )
        } catch {
            document = beforeDocument
            selection = beforeSelection
            assertDocumentValidInDebug()
            return nil
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

        case .deleteBlockSelection:
            try deleteBlockSelection(operations: &operations, changed: &changed)
        }
    }
}
