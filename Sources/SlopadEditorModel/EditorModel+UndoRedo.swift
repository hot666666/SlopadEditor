import SlopadCoreModel

// MARK: - EditorModel UndoRedo

package struct EditorHistoryStepResult: Sendable {
    package let documentChanged: Bool

    package init(documentChanged: Bool) {
        self.documentChanged = documentChanged
    }
}

extension EditorModel {
    package var historyAvailability: (canUndo: Bool, canRedo: Bool) {
        (!undoStack.isEmpty, !redoStack.isEmpty)
    }

    @discardableResult
    package func undo() -> EditorHistoryStepResult? {
        guard let transaction = undoStack.popLast() else { return nil }
        let previousSelection = selection
        let previousStoredMarks = storedMarks
        state = transaction.before
        redoStack.append(transaction)
        recordSelectionChange(from: previousSelection)
        recordStoredMarksChange(from: previousStoredMarks)
        recordCanonicalStructureChange(transaction.change.canonicalStructureChanged)
        assertDocumentValidInDebug()
        return EditorHistoryStepResult(documentChanged: transaction.change.documentChanged)
    }

    @discardableResult
    package func redo() -> EditorHistoryStepResult? {
        guard let transaction = redoStack.popLast() else { return nil }
        let previousSelection = selection
        let previousStoredMarks = storedMarks
        state = transaction.after
        undoStack.append(transaction)
        trimUndoStackToBudget()
        recordSelectionChange(from: previousSelection)
        recordStoredMarksChange(from: previousStoredMarks)
        recordCanonicalStructureChange(transaction.change.canonicalStructureChanged)
        assertDocumentValidInDebug()
        return EditorHistoryStepResult(documentChanged: transaction.change.documentChanged)
    }

    func trimUndoStackToBudget() {
        if undoConfiguration.maxTransactions <= 0 {
            undoStack.removeAll()
            return
        }
        while undoStack.count > undoConfiguration.maxTransactions {
            undoStack.removeFirst()
        }
        guard undoConfiguration.maxEstimatedBytes > 0 else {
            undoStack.removeAll()
            return
        }
        while undoStack.count > 1
            && undoStack.reduce(0, { $0 + $1.estimatedUndoCost })
                > undoConfiguration.maxEstimatedBytes
        {
            undoStack.removeFirst()
        }
    }

    func assertDocumentValidInDebug() {
        #if DEBUG
            state.document.assertValidInvariants()
        #endif
    }
}
