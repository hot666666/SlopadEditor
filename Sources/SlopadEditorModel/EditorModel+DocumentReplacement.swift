import SlopadCoreModel

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
    ) throws(EditorDocumentReplacementError) -> (
        selectionBefore: EditorSelection,
        change: EditorChange
    )? {
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

        guard documentChanged || beforeSelection != selectionAfter else {
            return nil
        }

        var afterDocument = candidateDocument
        if documentChanged {
            afterDocument.revision = beforeDocument.revision + 1
        }
        document = afterDocument
        selection = selectionAfter

        let changedBlockIDs = documentChanged
            ? Set(beforeDocument.blocks.keys).union(afterDocument.blocks.keys)
            : []
        let change = EditorChange(
            documentChanged: documentChanged,
            changedBlockIDs: changedBlockIDs,
            operations: documentChanged ? [.replaceDocument] : []
        )
        let transaction = EditorTransaction(
            beforeSnapshot: beforeDocument,
            afterSnapshot: afterDocument,
            selectionBefore: beforeSelection,
            selectionAfter: selectionAfter,
            change: change
        )
        undoStack.append(transaction)
        trimUndoStackToBudget()
        redoStack.removeAll()
        assertDocumentValidInDebug()
        return (selectionBefore: beforeSelection, change: change)
    }
}

extension EditorDocumentReplacementError {
    init(_ error: CanonicalDocumentReplacementValidationError) {
        switch error {
        case .emptyDocument:
            self = .emptyDocument
        case .duplicateBlockID(let blockID):
            self = .duplicateBlockID(blockID)
        case .invalidContent(let blockID):
            self = .invalidContent(blockID: blockID)
        case .missingParent(let blockID, let parentID):
            self = .missingParent(blockID: blockID, parentID: parentID)
        case .cycleDetected(let blockID):
            self = .cycleDetected(blockID)
        case .noncanonicalDepthFirstOrder:
            self = .noncanonicalDepthFirstOrder
        case .invalidSelection:
            self = .invalidSelection
        }
    }
}
