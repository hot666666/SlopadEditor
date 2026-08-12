// MARK: - Document TreeMutation

extension Document {
    package mutating func insertBlock(
        _ block: Block,
        parentID: BlockID? = nil,
        index: Int? = nil
    ) -> Result<Void, DocumentMutationResult.Failure> {
        guard blocks[block.id] == nil else {
            return .failure(.duplicateBlock(block.id))
        }
        if let parentID, blocks[parentID] == nil {
            return .failure(.missingBlock(parentID))
        }
        var block = block
        block.parentID = parentID
        block.childIDs = []
        blocks[block.id] = block
        var siblings = children(of: parentID)
        let insertionIndex = min(max(index ?? siblings.count, 0), siblings.count)
        siblings.insert(block.id, at: insertionIndex)
        replaceChildListWithoutRevision(siblings, of: parentID)
        revision += 1
        return .success(())
    }

    @discardableResult
    package mutating func removeSubtree(_ blockID: BlockID) -> Result<
        [BlockID], DocumentMutationResult.Failure
    > {
        guard let block = blocks[blockID] else {
            return .failure(.missingBlock(blockID))
        }
        var removed: [BlockID] = []
        for childID in block.childIDs {
            switch removeSubtree(childID) {
            case .success(let childRemoved):
                removed.append(contentsOf: childRemoved)

            case .failure(let failure):
                return .failure(failure)
            }
        }
        removeFromParentChildListWithoutRevision(blockID)
        blocks.removeValue(forKey: blockID)
        removed.append(blockID)
        revision += 1
        return .success(removed)
    }

    package mutating func moveSubtreeRange(
        _ blockIDs: [BlockID],
        toParentID parentID: BlockID?,
        index: Int
    ) -> Result<Void, DocumentMutationResult.Failure> {
        guard !blockIDs.isEmpty else { return .success(()) }
        if let parentID, blocks[parentID] == nil {
            return .failure(.missingBlock(parentID))
        }
        for blockID in blockIDs {
            guard blocks[blockID] != nil else { return .failure(.missingBlock(blockID)) }
            if let parentID, hasAncestor(blockID, of: parentID) || blockID == parentID {
                return .failure(.wouldCreateCycle(blockID))
            }
        }

        for blockID in blockIDs {
            removeFromParentChildListWithoutRevision(blockID)
        }
        var targetSiblings = children(of: parentID)
        let insertionIndex = min(max(index, 0), targetSiblings.count)
        targetSiblings.insert(contentsOf: blockIDs, at: insertionIndex)
        replaceChildListWithoutRevision(targetSiblings, of: parentID)
        for blockID in blockIDs {
            blocks[blockID]?.parentID = parentID
        }
        revision += 1
        return .success(())
    }
}
