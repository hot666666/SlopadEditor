import SlopadEditorCoreModel

// MARK: - Block Kind Commands

extension EditorModel {
    func setBlockKind(
        blockID: BlockID,
        kind: BlockKind,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        try requireDocumentMutationSuccess(
            state.document.setBlockKind(blockID: blockID, kind: kind))
        changed.insert(blockID)
        operations.append(.refreshMarker)
    }

    func toggleTodo(
        blockID: BlockID,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard let block = state.document.block(blockID) else { throw .abort }
        switch block.kind {
        case .todo(let isChecked):
            try setBlockKind(
                blockID: blockID, kind: .todo(isChecked: !isChecked), operations: &operations,
                changed: &changed)

        default:
            throw .abort
        }
    }
}
