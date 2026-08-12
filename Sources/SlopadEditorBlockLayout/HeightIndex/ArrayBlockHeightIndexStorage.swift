import SlopadCoreModel

// MARK: - ArrayBlockHeightIndexStorage

final class ArrayBlockHeightIndexStorage {
    private var entries: [BlockHeightIndexStorage.Entry]
    private var indicesByBlockID: [BlockID: Int]
    private var prefixSums: [Double]
    private var prefixSumsDirtyFrom: Int?

    init(entries: [BlockHeightIndexStorage.Entry]) {
        self.entries = entries
        self.indicesByBlockID = [:]
        self.prefixSums = [0]
        self.prefixSumsDirtyFrom = nil
        rebuildIndicesByBlockID(from: 0)
        markPrefixSumsDirty(from: 0)
    }

    var count: Int {
        entries.count
    }

    var totalHeight: Double {
        rebuildPrefixSumsIfNeeded()
        return prefixSums.last ?? 0
    }

    func entry(at index: Int) -> BlockHeightIndexStorage.Entry? {
        guard entries.indices.contains(index) else { return nil }
        return entries[index]
    }

    func index(of blockID: BlockID) -> Int? {
        indicesByBlockID[blockID]
    }

    func topY(for blockID: BlockID) -> Double? {
        guard let index = indicesByBlockID[blockID] else { return nil }
        rebuildPrefixSumsIfNeeded()
        return prefixSums[index]
    }

    func blockID(atY yOffset: Double) -> BlockID? {
        guard !entries.isEmpty else { return nil }
        rebuildPrefixSumsIfNeeded()
        guard yOffset < (prefixSums.last ?? 0) else { return nil }
        if yOffset < 0 {
            return entries.first?.blockID
        }
        let index = indexContainingPrefixPosition(yOffset)
        guard entries.indices.contains(index) else { return nil }
        return entries[index].blockID
    }

    func visibleRange(yOffset: Double, viewportHeight: Double) -> Range<Int> {
        guard viewportHeight > 0, count > 0 else { return 0..<0 }

        let startY = max(0, yOffset)
        guard startY < totalHeight else { return count..<count }

        rebuildPrefixSumsIfNeeded()
        let start = indexContainingPrefixPosition(startY)
        let end = min(count, firstIndexWithPrefixSum(atLeast: startY + viewportHeight))
        return start..<max(start, end)
    }

    func insert(_ item: BlockHeightIndexStorage.Entry, at index: Int) {
        guard indicesByBlockID[item.blockID] == nil else { return }
        let insertionIndex = min(max(0, index), entries.count)
        entries.insert(item, at: insertionIndex)
        rebuildIndicesByBlockID(from: insertionIndex)
        markPrefixSumsDirty(from: insertionIndex)
    }

    @discardableResult
    func remove(blockID: BlockID) -> BlockHeightIndexStorage.Entry? {
        guard let index = indicesByBlockID.removeValue(forKey: blockID) else { return nil }
        let removed = entries.remove(at: index)
        rebuildIndicesByBlockID(from: index)
        markPrefixSumsDirty(from: index)
        return removed
    }

    func updateHeight(blockID: BlockID, height: Double) {
        guard let index = indicesByBlockID[blockID] else { return }
        entries[index] = BlockHeightIndexStorage.Entry(blockID: blockID, height: height)
        markPrefixSumsDirty(from: index)
    }

    func validateInvariantsForTesting() -> Bool {
        guard entries.count == indicesByBlockID.count else { return false }

        var seen: Set<BlockID> = []
        for (index, item) in entries.enumerated() {
            guard seen.insert(item.blockID).inserted else { return false }
            guard indicesByBlockID[item.blockID] == index else { return false }
        }

        rebuildPrefixSumsIfNeeded()
        guard prefixSums.count == entries.count + 1 else { return false }
        var runningTotal = 0.0
        for (index, item) in entries.enumerated() {
            guard prefixSums[index] == runningTotal else { return false }
            runningTotal += item.height
        }
        guard prefixSums.last == runningTotal else { return false }
        return true
    }

    private func rebuildIndicesByBlockID(from startIndex: Int) {
        if startIndex == 0 {
            indicesByBlockID.removeAll(keepingCapacity: true)
        }
        guard startIndex < entries.count else { return }
        for index in startIndex..<entries.count {
            indicesByBlockID[entries[index].blockID] = index
        }
    }

    private func markPrefixSumsDirty(from index: Int) {
        let dirtyIndex = min(max(0, index), entries.count)
        prefixSumsDirtyFrom = min(prefixSumsDirtyFrom ?? dirtyIndex, dirtyIndex)
    }

    private func rebuildPrefixSumsIfNeeded() {
        guard let dirtyIndex = prefixSumsDirtyFrom else { return }

        var rebuildStart = min(dirtyIndex, entries.count)
        if prefixSums.count < rebuildStart + 1 {
            prefixSums = [0]
            rebuildStart = 0
        } else if prefixSums.count > rebuildStart + 1 {
            prefixSums.removeSubrange((rebuildStart + 1)..<prefixSums.count)
        }

        var runningTotal = prefixSums[rebuildStart]
        if rebuildStart < entries.count {
            prefixSums.reserveCapacity(entries.count + 1)
            for index in rebuildStart..<entries.count {
                runningTotal += entries[index].height
                prefixSums.append(runningTotal)
            }
        }

        prefixSumsDirtyFrom = nil
    }

    private func indexContainingPrefixPosition(_ position: Double) -> Int {
        firstPrefixSumGreaterThan(position) - 1
    }

    private func firstPrefixSumGreaterThan(_ value: Double) -> Int {
        var lowerBound = 0
        var upperBound = prefixSums.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if prefixSums[middle] > value {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }
        return lowerBound
    }

    private func firstIndexWithPrefixSum(atLeast value: Double) -> Int {
        var lowerBound = 0
        var upperBound = prefixSums.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if prefixSums[middle] >= value {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }
        return lowerBound
    }
}

#if SLOPAD_TREE_METRICS
    extension ArrayBlockHeightIndexStorage {
        var visitCount: Int {
            0
        }

        func resetVisitCount() {}
    }
#endif
