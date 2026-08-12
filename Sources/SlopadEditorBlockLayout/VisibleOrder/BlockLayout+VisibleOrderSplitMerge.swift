import SlopadCoreModel

// MARK: - Visible Order Split Merge

extension BlockLayout {
    func applyVisibleOrderSplit(
        original: BlockID,
        created: BlockID,
        document: Document,
        visibleIndex: VisibleBlockIndex,
        changeSet: inout BlockLayoutChangeSet
    ) -> Bool {
        guard
            let originalIndex = visibleIndex.index(of: original),
            let originalVisible = visibleIndex.entry(for: original)
        else {
            return false
        }

        let createdVisible = VisibleBlock(
            blockID: created,
            depth: originalVisible.depth,
            parentID: document.parentID(of: created)
        )
        guard visibleIndex.insert(createdVisible, at: originalIndex + 1) else {
            return false
        }

        for childID in document.children(of: created) {
            guard let childVisible = visibleIndex.entry(for: childID) else { continue }
            _ = visibleIndex.update(
                VisibleBlock(
                    blockID: childVisible.blockID,
                    depth: childVisible.depth,
                    parentID: created
                )
            )
        }

        changeSet.insertedBlockIDs.append(created)
        changeSet.updatedBlockIDs.insert(original)
        return true
    }

    func applyVisibleOrderMerge(
        target: BlockID,
        source: BlockID,
        visibleIndex: VisibleBlockIndex,
        changeSet: inout BlockLayoutChangeSet
    ) -> Bool {
        guard
            let targetVisible = visibleIndex.entry(for: target),
            let sourceSpan = visibleIndex.spanEntries(rootID: source)
        else {
            return false
        }

        let targetDepth = targetVisible.depth
        let sourceChildIDs = sourceSpan.filter { $0.parentID == source }.map(\.blockID)
        var depthChangedBlockIDs: [BlockID] = []
        for childID in sourceChildIDs {
            guard let childSpan = visibleIndex.spanEntries(rootID: childID),
                let childRoot = childSpan.first
            else {
                return false
            }
            let depthDelta = targetDepth + 1 - childRoot.depth
            if depthDelta != 0 {
                depthChangedBlockIDs.append(contentsOf: childSpan.map(\.blockID))
            }
            for visible in childSpan {
                let updatedVisible = VisibleBlock(
                    blockID: visible.blockID,
                    depth: visible.depth + depthDelta,
                    parentID: visible.blockID == childID ? target : visible.parentID
                )
                _ = visibleIndex.update(updatedVisible)
            }
        }

        guard visibleIndex.remove(blockID: source) != nil else {
            return false
        }
        changeSet.removedBlockIDs.append(source)
        if !depthChangedBlockIDs.isEmpty {
            changeSet.removedBlockIDs.append(contentsOf: depthChangedBlockIDs)
            changeSet.insertedBlockIDs.append(contentsOf: depthChangedBlockIDs)
        }
        changeSet.updatedBlockIDs.insert(target)
        return true
    }
}
