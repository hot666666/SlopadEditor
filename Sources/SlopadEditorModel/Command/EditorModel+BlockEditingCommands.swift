import SlopadCoreModel

// MARK: - Block Editing Commands

extension EditorModel {
    func splitBlock(
        blockID: BlockID,
        offset: Int,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        let createdID = BlockID()
        let split: DocumentMutationResult.Split
        switch state.document.splitBlock(blockID: blockID, offset: offset, newBlockID: createdID) {
        case .success(let result):
            split = result

        case .failure:
            throw .abort
        }
        state.selection = .caret(blockID: createdID, offset: 0)
        changed.formUnion([blockID, createdID])
        changed.formUnion(split.transferredChildIDs)
        operations.append(.splitBlock(original: blockID, created: createdID))
    }

    func mergeBlocks(
        target: BlockID,
        source: BlockID,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        let merge: DocumentMutationResult.Merge
        switch state.document.mergeBlocks(target: target, source: source) {
        case .success(let result):
            merge = result

        case .failure:
            throw .abort
        }
        state.selection = .caret(blockID: target, offset: merge.targetOriginalLength)
        changed.formUnion([target, source])
        changed.formUnion(merge.appendedChildIDs)
        operations.append(.mergeBlocks(target: target, source: source))
    }
}
