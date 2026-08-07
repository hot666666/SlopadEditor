import SlopadCoreModel

// MARK: - EditorModel EnterKeyCommands

extension EditorModel {
    func handleEnter(
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard case .caret(let position) = selection else {
            throw .abort
        }
        let blockID = position.blockID
        guard let block = state.document.block(blockID) else { throw .abort }
        if block.kind.isListLike && block.content.text.isEmpty {
            if !block.childIDs.isEmpty || block.parentID == nil {
                try setBlockKind(
                    blockID: blockID, kind: .paragraph, operations: &operations, changed: &changed)
                return
            }
            try outdent(
                selection: BlockSelection(blockIDs: [blockID]),
                operations: &operations,
                changed: &changed
            )
            try setBlockKind(
                blockID: blockID, kind: .paragraph, operations: &operations, changed: &changed)
            return
        }
        try splitBlock(
            blockID: blockID, offset: position.offset, operations: &operations,
            changed: &changed)
    }

    func handleShiftEnter(
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        try insertText("\n", operations: &operations, changed: &changed)
    }
}

extension BlockKind {
    fileprivate var isListLike: Bool {
        switch self {
        case .unorderedListItem, .orderedListItem, .todo:
            true
        default:
            false
        }
    }
}
