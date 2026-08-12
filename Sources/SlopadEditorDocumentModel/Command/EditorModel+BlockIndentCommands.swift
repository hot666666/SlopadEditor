import SlopadCoreModel

// MARK: - Block Indent Commands

extension EditorModel {
    func indent(
        selection blockSelection: BlockSelection,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        let moving = state.document.topLevelBlockIDs(blockSelection.blockIDs)
        guard let first = moving.first else {
            throw .abort
        }
        let parentID = state.document.parentID(of: first)
        let siblings = state.document.children(of: parentID)
        guard let firstSiblingIndex = siblings.firstIndex(of: first), firstSiblingIndex > 0 else {
            throw .abort
        }
        let newParentID = siblings[firstSiblingIndex - 1]
        guard !moving.contains(newParentID), state.document.containsBlock(newParentID) else {
            throw .abort
        }
        guard state.document.parentID(of: first) != newParentID else {
            throw .abort
        }
        try requireDocumentMutationSuccess(
            state.document.moveSubtreeRange(
                moving,
                toParentID: newParentID,
                index: state.document.children(of: newParentID).count
            ))
        state.selection = .blocks(blockSelection)
        changed.formUnion(moving)
        changed.insert(newParentID)
        operations.append(.indent(blockIDs: moving))
    }
}
