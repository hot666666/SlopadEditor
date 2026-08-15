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
    case customTypeIDEmpty(BlockID)
    case customPayloadTooLarge(BlockID)
    case customBlockCarriesText(BlockID)
    case customBlockHasChildren(BlockID)
    case customBlockNotPreserved(BlockID)
}

extension EditorModel {
    /// Requires every custom block in the current document to survive the post-image intact.
    ///
    /// The editor cannot decode a payload, so it cannot distinguish an intentional rewrite
    /// from an accidental loss — and the most likely way to lose one is a patch produced by
    /// round-tripping the document through a format that has no representation for custom
    /// blocks. Identity, type, version, and payload bytes are compared; position and parent
    /// are not, because an ordinary patch that reorders paragraphs also moves whatever sits
    /// between them.
    private func validateCustomBlocksSurvive(
        in blockInputs: [EditorBlockInput]
    ) throws(EditorDocumentReplacementError) {
        var survivors: [BlockID: BlockKind] = [:]
        for input in blockInputs where input.kind.isCustom {
            survivors[input.id] = input.kind
        }

        for blockID in document.blocks.keys {
            guard let existing = document.blocks[blockID], existing.kind.isCustom else {
                continue
            }
            guard survivors[blockID] == existing.kind else {
                throw .customBlockNotPreserved(blockID)
            }
        }
    }

    @discardableResult
    package func replaceDocument(
        with blockInputs: [EditorBlockInput],
        selection selectionAfter: EditorSelection,
        preservingCustomBlocks: Bool = true
    ) throws(EditorDocumentReplacementError) -> EditorCommandResult {
        do {
            try Document.validateCanonicalReplacement(
                blockInputs: blockInputs,
                selection: selectionAfter
            )
        } catch let error {
            throw EditorDocumentReplacementError(error)
        }

        if preservingCustomBlocks {
            try validateCustomBlocksSurvive(in: blockInputs)
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
        case .documentInput(.customTypeIDEmpty(let blockID)):
            self = .customTypeIDEmpty(blockID)
        case .documentInput(.customPayloadTooLarge(let blockID)):
            self = .customPayloadTooLarge(blockID)
        case .documentInput(.customBlockCarriesText(let blockID)):
            self = .customBlockCarriesText(blockID)
        case .documentInput(.customBlockHasChildren(let blockID)):
            self = .customBlockHasChildren(blockID)
        case .invalidSelection:
            self = .invalidSelection
        }
    }
}
