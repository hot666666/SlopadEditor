import SlopadEditorCoreModel

// MARK: - Editor Document Replacement

package enum EditorDocumentReplacementError: Error, Hashable, Sendable {
    case emptyDocument
    case duplicateBlockID(BlockID)
    case invalidContent(blockID: BlockID)
    case missingParent(blockID: BlockID, parentID: BlockID)
    case cycleDetected(BlockID)
    case noncanonicalDepthFirstOrder
    case invalidSelection
}

extension EditorModel {
    @discardableResult
    package func replaceDocument(
        with blockInputs: [EditorBlockInput],
        selection selectionAfter: EditorSelection
    ) throws(EditorDocumentReplacementError) -> EditorCommandResult {
        do {
            try Document.validateCanonicalReplacement(
                blockInputs: blockInputs,
                selection: selectionAfter
            )
        } catch let error {
            throw EditorDocumentReplacementError(error)
        }

        let beforeDocument = document
        let beforeSelection = selection
        let candidateDocument = Document(
            blockInputs: blockInputs,
            revision: beforeDocument.revision
        )
        let documentChanged = !beforeDocument.hasSameCanonicalContent(as: candidateDocument)
        let canonicalStructureChanged = !beforeDocument.hasSameCanonicalStructure(
            as: candidateDocument
        )

        guard documentChanged || beforeSelection != selectionAfter else {
            return .notApplicable
        }

        var afterDocument = candidateDocument
        if documentChanged {
            afterDocument.revision = beforeDocument.revision + 1
        }
        let beforeState = state
        // A whole new document is not a place the caret was aiming at, so anything armed for
        // the old one is dropped. Agent patches land here too: a style armed before a patch
        // must not attach itself to unrelated replacement content.
        state = EditorState(document: afterDocument, selection: selectionAfter)

        let changedBlockIDs =
            documentChanged
            ? Set(beforeDocument.blocks.keys).union(afterDocument.blocks.keys)
            : []
        let change = EditorChange(
            documentChanged: documentChanged,
            canonicalStructureChanged: canonicalStructureChanged,
            changedBlockIDs: changedBlockIDs,
            operations: documentChanged ? [.replaceDocument] : []
        )
        let transaction = EditorTransaction(before: beforeState, after: state, change: change)
        undoStack.append(transaction)
        trimUndoStackToBudget()
        redoStack.removeAll()
        recordSelectionChange(from: beforeSelection)
        recordStoredMarksChange(from: beforeState.storedMarks)
        recordCanonicalStructureChange(canonicalStructureChanged)
        assertDocumentValidInDebug()
        let outcome = EditorCommandOutcome(selectionBefore: beforeSelection, change: change)
        return documentChanged ? .document(outcome) : .selectionOnly(outcome)
    }
}

extension EditorDocumentReplacementError {
    init(_ error: CanonicalDocumentReplacementValidationError) {
        switch error {
        case .documentInput(.emptyDocument):
            self = .emptyDocument
        case .documentInput(.duplicateBlockID(let blockID)):
            self = .duplicateBlockID(blockID)
        case .documentInput(.invalidContent(let blockID)):
            self = .invalidContent(blockID: blockID)
        case .documentInput(.missingParent(let blockID, let parentID)):
            self = .missingParent(blockID: blockID, parentID: parentID)
        case .documentInput(.cycleDetected(let blockID)):
            self = .cycleDetected(blockID)
        case .documentInput(.noncanonicalDepthFirstOrder):
            self = .noncanonicalDepthFirstOrder
        case .invalidSelection:
            self = .invalidSelection
        }
    }
}
