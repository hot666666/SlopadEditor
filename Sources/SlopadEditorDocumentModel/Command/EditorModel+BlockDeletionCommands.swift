import SlopadEditorCoreModel

// MARK: - Block Deletion Commands

extension EditorModel {
    func replaceBlockSelectionWithText(
        _ text: String,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard case .blocks(let blockSelection) = selection else { throw .abort }
        let ordered = state.document.topLevelBlockIDs(blockSelection.blockIDs)
        guard
            let survivorID = ordered.first,
            state.document.block(survivorID) != nil
        else { throw .abort }

        var removed: [BlockID] = []
        let survivorChildren = state.document.children(of: survivorID)
        for blockID in survivorChildren + Array(ordered.dropFirst()) {
            switch state.document.removeSubtree(blockID) {
            case .success(let removedSubtree):
                removed.append(contentsOf: removedSubtree)
            case .failure:
                throw .abort
            }
        }
        try requireDocumentMutationSuccess(
            state.document.setBlockKind(blockID: survivorID, kind: .paragraph)
        )
        try requireDocumentMutationSuccess(
            state.document.replaceContent(
                blockID: survivorID,
                content: BlockContent(text: text)
            )
        )
        state.selection = .caret(blockID: survivorID, offset: text.count)
        changed.formUnion(removed)
        changed.insert(survivorID)
        if !removed.isEmpty {
            operations.append(.deleteBlocks(blockIDs: removed))
        }
        operations.append(.refreshMarker)
    }

    func deleteBlockSelection(
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard case .blocks(let blockSelection) = selection else {
            throw .abort
        }
        let ordered = state.document.topLevelBlockIDs(blockSelection.blockIDs)
        guard !ordered.isEmpty else { throw .abort }
        let allVisibleSelected =
            !state.document.rootBlockIDs.isEmpty
            && ordered == state.document.rootBlockIDs
        var removed: [BlockID] = []
        for blockID in ordered {
            switch state.document.removeSubtree(blockID) {
            case .success(let removedSubtree):
                removed.append(contentsOf: removedSubtree)

            case .failure:
                throw .abort
            }
        }
        changed.formUnion(removed)
        operations.append(.deleteBlocks(blockIDs: removed))

        if allVisibleSelected {
            guard let resetID = ordered.first else { throw .abort }
            state.document = .singleParagraph("", id: resetID)
            state.selection = .caret(blockID: resetID, offset: 0)
            changed.insert(resetID)
            operations.append(.resetDocumentToEmptyParagraph(blockID: resetID))
        } else {
            state.selection = .inactive
        }
    }
}
