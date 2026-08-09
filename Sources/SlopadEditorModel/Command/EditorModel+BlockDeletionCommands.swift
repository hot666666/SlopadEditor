import SlopadCoreModel

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
            let firstBlock = state.document.block(survivorID)
        else { throw .abort }
        let parentID = firstBlock.parentID
        let insertionIndex = state.document.children(of: parentID).firstIndex(of: survivorID) ?? 0

        var removed: [BlockID] = []
        for blockID in ordered {
            switch state.document.removeSubtree(blockID) {
            case .success(let removedSubtree):
                removed.append(contentsOf: removedSubtree)
            case .failure:
                throw .abort
            }
        }
        try requireDocumentMutationSuccess(
            state.document.insertBlock(
                Block(
                    id: survivorID,
                    kind: .paragraph,
                    content: BlockContent(text: text)
                ),
                parentID: parentID,
                index: insertionIndex
            )
        )
        state.selection = .caret(blockID: survivorID, offset: text.count)
        changed.formUnion(removed)
        changed.insert(survivorID)
        operations.append(.deleteBlocks(blockIDs: removed))
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
