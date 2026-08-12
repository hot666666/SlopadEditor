import SlopadCoreModel

// MARK: - VisibleBlockIndex

final class VisibleBlockIndex {
    private var entries: [VisibleBlock]
    private var indexByBlockID: [BlockID: Int]
    private(set) var revision: Int

    convenience init(document: Document) {
        var entries: [VisibleBlock] = []
        var visitedBlockIDs: Set<BlockID> = []

        func appendVisibleSubtree(blockID: BlockID, depth: Int) {
            guard visitedBlockIDs.insert(blockID).inserted else { return }
            guard let block = document.blocks[blockID] else { return }

            entries.append(
                VisibleBlock(blockID: block.id, depth: depth, parentID: block.parentID)
            )

            for childID in block.childIDs {
                appendVisibleSubtree(blockID: childID, depth: depth + 1)
            }
        }

        for rootID in document.rootBlockIDs {
            appendVisibleSubtree(blockID: rootID, depth: 0)
        }
        self.init(entries)
    }

    init(_ entries: [VisibleBlock], revision: Int? = nil) {
        var uniqueEntries: [VisibleBlock] = []
        var seenBlockIDs: Set<BlockID> = []
        uniqueEntries.reserveCapacity(entries.count)
        for entry in entries where seenBlockIDs.insert(entry.blockID).inserted {
            uniqueEntries.append(entry)
        }

        self.entries = uniqueEntries
        self.indexByBlockID = Self.buildIndexByBlockID(uniqueEntries)
        self.revision = revision ?? Self.computeRevision(uniqueEntries)
    }

    var count: Int {
        entries.count
    }

    func entry(for blockID: BlockID) -> VisibleBlock? {
        guard let index = indexByBlockID[blockID] else { return nil }
        return entries[index]
    }

    func entry(at index: Int) -> VisibleBlock? {
        guard entries.indices.contains(index) else { return nil }
        return entries[index]
    }

    func index(of blockID: BlockID) -> Int? {
        indexByBlockID[blockID]
    }

    func entries(in range: Range<Int>) -> [VisibleBlock] {
        guard !range.isEmpty else { return [] }
        let boundedRange = max(0, range.lowerBound)..<min(count, range.upperBound)
        guard !boundedRange.isEmpty else { return [] }
        return Array(entries[boundedRange])
    }

    func entriesSnapshot() -> [VisibleBlock] {
        entries
    }

    @discardableResult
    func insert(_ entry: VisibleBlock, at index: Int) -> Bool {
        guard indexByBlockID[entry.blockID] == nil else { return false }
        entries.insert(entry, at: max(0, min(index, count)))
        rebuildIndexByBlockID()
        revision &+= 1
        return true
    }

    @discardableResult
    func insert(contentsOf entries: [VisibleBlock], at index: Int) -> Bool {
        guard !entries.isEmpty else { return true }
        var insertedBlockIDs: Set<BlockID> = []
        insertedBlockIDs.reserveCapacity(entries.count)
        for entry in entries {
            guard insertedBlockIDs.insert(entry.blockID).inserted,
                indexByBlockID[entry.blockID] == nil
            else {
                return false
            }
        }

        let insertionIndex = max(0, min(index, count))
        self.entries.insert(contentsOf: entries, at: insertionIndex)
        rebuildIndexByBlockID()
        revision &+= 1
        return true
    }

    @discardableResult
    func remove(blockID: BlockID) -> VisibleBlock? {
        guard let index = indexByBlockID[blockID] else { return nil }
        let removed = entries.remove(at: index)
        rebuildIndexByBlockID()
        revision &+= 1
        return removed
    }

    @discardableResult
    func remove(blockIDs: [BlockID]) -> [VisibleBlock] {
        guard !blockIDs.isEmpty else { return [] }
        let requestedBlockIDs = Set(blockIDs)
        let removedEntriesByBlockID = Dictionary(
            uniqueKeysWithValues:
                entries
                .filter { requestedBlockIDs.contains($0.blockID) }
                .map { ($0.blockID, $0) }
        )
        var emittedBlockIDs: Set<BlockID> = []
        var removedEntries: [VisibleBlock] = []
        for blockID in blockIDs {
            if emittedBlockIDs.insert(blockID).inserted,
                let removed = removedEntriesByBlockID[blockID]
            {
                removedEntries.append(removed)
            }
        }
        if !removedEntries.isEmpty {
            entries.removeAll { requestedBlockIDs.contains($0.blockID) }
            rebuildIndexByBlockID()
            revision &+= 1
        }
        return removedEntries
    }

    @discardableResult
    func update(_ entry: VisibleBlock) -> Bool {
        guard let index = indexByBlockID[entry.blockID] else { return false }
        entries[index] = entry
        revision &+= 1
        return true
    }

    func spanEntries(rootID: BlockID) -> [VisibleBlock]? {
        guard
            let startIndex = index(of: rootID),
            let endIndex = subtreeEndIndex(startingAt: startIndex)
        else {
            return nil
        }
        return entries(in: startIndex..<endIndex)
    }

    func subtreeEndIndex(startingAt startIndex: Int) -> Int? {
        guard let root = entry(at: startIndex) else { return nil }
        let rootDepth = root.depth
        var index = startIndex + 1
        while let entry = entry(at: index), entry.depth > rootDepth {
            index += 1
        }
        return index
    }

    func removeAll() {
        entries.removeAll()
        indexByBlockID.removeAll()
        revision &+= 1
    }
}

// MARK: - Index Map and Revision

extension VisibleBlockIndex {
    private func rebuildIndexByBlockID() {
        indexByBlockID = Self.buildIndexByBlockID(entries)
    }

    private static func buildIndexByBlockID(_ entries: [VisibleBlock]) -> [BlockID: Int] {
        var result: [BlockID: Int] = [:]
        result.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() where result[entry.blockID] == nil {
            result[entry.blockID] = index
        }
        return result
    }

    private static func computeRevision(_ entries: [VisibleBlock]) -> Int {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.blockID)
            hasher.combine(entry.depth)
            hasher.combine(entry.parentID)
        }
        return hasher.finalize()
    }
}
