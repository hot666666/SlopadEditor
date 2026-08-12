import SlopadCoreModel

// MARK: - Visible Order Relocation

extension BlockLayout {
    func relocateVisibleOrderSpans(
        blockIDs: [BlockID],
        document: Document,
        visibleIndex: VisibleBlockIndex,
        changeSet: inout BlockLayoutChangeSet
    ) -> Bool {
        guard !blockIDs.isEmpty else { return false }

        var spans: [(rootID: BlockID, entries: [VisibleBlock], rootDepth: Int)] = []
        var occupiedBlockIDs: Set<BlockID> = []
        for rootID in blockIDs {
            guard let spanEntries = visibleIndex.spanEntries(rootID: rootID),
                let root = spanEntries.first
            else {
                return false
            }
            guard spanEntries.allSatisfy({ occupiedBlockIDs.insert($0.blockID).inserted })
            else {
                return false
            }
            spans.append((rootID: rootID, entries: spanEntries, rootDepth: root.depth))
        }

        for span in spans {
            _ = visibleIndex.remove(blockIDs: span.entries.map(\.blockID))
        }

        var adjustedSpans: [(rootID: BlockID, entries: [VisibleBlock], rootDepth: Int)] = []
        var movedBlockIDs: [BlockID] = []
        var depthChangedBlockIDs: [BlockID] = []
        for span in spans {
            guard let finalDepth = document.blockDepth(of: span.rootID) else { return false }
            let depthDelta = finalDepth - span.rootDepth
            var adjustedEntries = span.entries
            for index in adjustedEntries.indices {
                let entry = adjustedEntries[index]
                adjustedEntries[index] = VisibleBlock(
                    blockID: entry.blockID,
                    depth: entry.depth + depthDelta,
                    parentID: index == adjustedEntries.startIndex
                        ? document.parentID(of: span.rootID)
                        : entry.parentID
                )
            }
            if depthDelta == 0 {
                movedBlockIDs.append(contentsOf: adjustedEntries.map(\.blockID))
            } else {
                depthChangedBlockIDs.append(contentsOf: adjustedEntries.map(\.blockID))
            }
            adjustedSpans.append(
                (rootID: span.rootID, entries: adjustedEntries, rootDepth: finalDepth)
            )
        }

        let sortedSpans = adjustedSpans.sorted {
            (document.blockOrderPath(for: $0.rootID) ?? [])
                .lexicographicallyPrecedes(document.blockOrderPath(for: $1.rootID) ?? [])
        }
        for span in sortedSpans {
            guard
                let insertionIndex = visibleOrderInsertionIndex(
                    for: span.rootID,
                    in: visibleIndex,
                    document: document
                )
            else {
                return false
            }
            guard visibleIndex.insert(contentsOf: span.entries, at: insertionIndex) else {
                return false
            }
        }

        changeSet.movedBlockIDs.append(contentsOf: movedBlockIDs)
        changeSet.removedBlockIDs.append(contentsOf: depthChangedBlockIDs)
        changeSet.insertedBlockIDs.append(contentsOf: depthChangedBlockIDs)
        return true
    }

    private func visibleOrderInsertionIndex(
        for blockID: BlockID,
        in visibleIndex: VisibleBlockIndex,
        document: Document
    ) -> Int? {
        let parentID = document.parentID(of: blockID)
        let siblings = document.children(of: parentID)
        guard let siblingIndex = siblings.firstIndex(of: blockID) else {
            return nil
        }

        let nextSiblingStart = siblings.index(after: siblingIndex)
        if nextSiblingStart < siblings.endIndex {
            for siblingID in siblings[nextSiblingStart...] {
                if let index = visibleIndex.index(of: siblingID) {
                    return index
                }
            }
        }

        if let parentID {
            guard
                let parentIndex = visibleIndex.index(of: parentID),
                let parentRangeEnd = visibleIndex.subtreeEndIndex(startingAt: parentIndex)
            else {
                return nil
            }
            return parentRangeEnd
        }
        return visibleIndex.count
    }
}
