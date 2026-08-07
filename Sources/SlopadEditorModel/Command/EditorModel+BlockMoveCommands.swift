import SlopadCoreModel

// MARK: - Block Move Commands

extension EditorModel {
    func move(
        selection blockSelection: BlockSelection,
        to target: BlockDropTarget,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        let moving = state.document.topLevelBlockIDs(blockSelection.blockIDs)
        guard !moving.isEmpty else { throw .abort }
        guard state.document.containsBlock(target.blockID) else {
            throw .abort
        }
        guard !state.document.hasAncestorOrSelf(in: Set(moving), of: target.blockID) else {
            throw .abort
        }

        let targetParentID = state.document.parentID(of: target.blockID)
        let targetSiblings = state.document.children(of: targetParentID)
        let siblingsAfterRemoval = targetSiblings.filter { !moving.contains($0) }
        guard let targetIndexAfterRemoval = siblingsAfterRemoval.firstIndex(of: target.blockID)
        else {
            throw .abort
        }

        let insertionIndex: Int
        switch target.placement {
        case .before:
            insertionIndex = targetIndexAfterRemoval
        case .after:
            insertionIndex = targetIndexAfterRemoval + 1
        }

        if moving.allSatisfy({ state.document.parentID(of: $0) == targetParentID }) {
            var finalSiblings = siblingsAfterRemoval
            finalSiblings.insert(contentsOf: moving, at: min(insertionIndex, finalSiblings.count))
            guard finalSiblings != targetSiblings else { throw .abort }
        }

        try requireDocumentMutationSuccess(
            state.document.moveSubtreeRange(
                moving,
                toParentID: targetParentID,
                index: insertionIndex
            ))

        state.selection = .blocks(blockSelection)
        changed.formUnion(moving)
        if let targetParentID {
            changed.insert(targetParentID)
        }
        operations.append(.moveBlocks(blockIDs: moving))
    }
}
