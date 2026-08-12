// MARK: - Document ChildListMutation

extension Document {
    mutating func replaceChildListWithoutRevision(
        _ childIDs: [BlockID], of parentID: BlockID?
    ) {
        if let parentID {
            blocks[parentID]?.childIDs = childIDs
        } else {
            rootBlockIDs = childIDs
        }
    }

    mutating func removeFromParentChildListWithoutRevision(_ blockID: BlockID) {
        guard let parentID = blocks[blockID]?.parentID else {
            rootBlockIDs.removeAll { $0 == blockID }
            return
        }
        blocks[parentID]?.childIDs.removeAll { $0 == blockID }
    }
}
