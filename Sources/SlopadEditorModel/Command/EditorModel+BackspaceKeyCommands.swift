import SlopadCoreModel

// MARK: - EditorModel BackspaceKeyCommands

extension EditorModel {
    func handleBackspace(
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        switch selection {
        case .inactive:
            throw .abort

        case .text(let textSelection):
            guard textSelection.isSingleBlock, let range = textSelection.rangeInSingleBlock else {
                throw .abort
            }
            try deleteText(
                blockID: textSelection.anchor.blockID, range: range, operations: &operations,
                changed: &changed)

        case .blocks:
            try deleteBlockSelection(operations: &operations, changed: &changed)

        case .caret(let position):
            let blockID = position.blockID
            guard let block = state.document.block(blockID) else {
                throw .abort
            }
            if position.offset > 0 {
                let range = TextRange(position.offset - 1, position.offset)
                try deleteText(
                    blockID: blockID, range: range, operations: &operations, changed: &changed
                )
                return
            }

            if block.kind != .paragraph {
                try setBlockKind(
                    blockID: blockID,
                    kind: .paragraph,
                    operations: &operations,
                    changed: &changed
                )
                return
            }

            if block.parentID != nil && state.document.previousSiblingID(of: blockID) == nil {
                try outdent(
                    selection: BlockSelection(blockIDs: [blockID]), operations: &operations,
                    changed: &changed)
                return
            }

            guard let previousVisible = previousVisibleBlockID(before: blockID) else {
                throw .abort
            }
            try mergeBlocks(
                target: previousVisible, source: blockID, operations: &operations, changed: &changed
            )
        }
    }

    private func previousVisibleBlockID(before blockID: BlockID) -> BlockID? {
        guard state.document.containsBlock(blockID) else { return nil }

        let parentID = state.document.parentID(of: blockID)
        let siblings = state.document.children(of: parentID)
        guard let siblingIndex = siblings.firstIndex(of: blockID) else { return nil }
        if siblingIndex > 0 {
            return lastVisibleDescendant(of: siblings[siblingIndex - 1])
        }
        return parentID
    }

    private func lastVisibleDescendant(of blockID: BlockID) -> BlockID {
        var currentID = blockID
        while let lastChildID = state.document.children(of: currentID).last {
            currentID = lastChildID
        }
        return currentID
    }
}
