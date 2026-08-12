import SlopadCoreModel

// MARK: - BlockHeightIndexStorageAdapter

#if SLOPAD_HEIGHT_INDEX_ARRAY
    private typealias BlockHeightIndexStorageAdapter = ArrayBlockHeightIndexStorage
#else
    private typealias BlockHeightIndexStorageAdapter = RBTreeBlockHeightIndexStorage
#endif

// MARK: - BlockHeightIndexStorage

package final class BlockHeightIndexStorage {
    struct Entry {
        let blockID: BlockID
        let height: Double

        init(blockID: BlockID, height: Double) {
            self.blockID = blockID
            self.height = height
        }
    }

    private let adapter: BlockHeightIndexStorageAdapter

    package convenience init() {
        self.init(entries: [])
    }

    init(entries: [Entry]) {
        let uniqueEntries = Self.uniqueEntries(entries)
        self.adapter = BlockHeightIndexStorageAdapter(entries: uniqueEntries)
    }

    var count: Int {
        adapter.count
    }

    package var totalHeight: Double {
        adapter.totalHeight
    }

    func entry(at index: Int) -> Entry? {
        adapter.entry(at: index)
    }

    package func index(of blockID: BlockID) -> Int? {
        adapter.index(of: blockID)
    }

    func topY(for blockID: BlockID) -> Double? {
        adapter.topY(for: blockID)
    }

    package func blockID(atY yOffset: Double) -> BlockID? {
        adapter.blockID(atY: yOffset)
    }

    func visibleRange(yOffset: Double, viewportHeight: Double) -> Range<Int> {
        adapter.visibleRange(yOffset: yOffset, viewportHeight: viewportHeight)
    }

    package func insert(blockID: BlockID, height: Double, at index: Int) {
        insert(Entry(blockID: blockID, height: height), at: index)
    }

    func insert(_ item: Entry, at index: Int) {
        adapter.insert(item, at: index)
    }

    @discardableResult
    func remove(blockID: BlockID) -> Entry? {
        adapter.remove(blockID: blockID)
    }

    package func updateHeight(blockID: BlockID, height: Double) {
        adapter.updateHeight(blockID: blockID, height: height)
    }

    #if SLOPAD_TREE_METRICS
        package var visitCount: Int {
            adapter.visitCount
        }

        package func resetVisitCount() {
            adapter.resetVisitCount()
        }
    #endif

    private static func uniqueEntries(_ entries: [Entry]) -> [Entry] {
        var uniqueEntries: [Entry] = []
        var seenBlockIDs: Set<BlockID> = []
        uniqueEntries.reserveCapacity(entries.count)
        for entry in entries where seenBlockIDs.insert(entry.blockID).inserted {
            uniqueEntries.append(entry)
        }
        return uniqueEntries
    }
}

extension BlockHeightIndexStorage {
    func validateInvariantsForTesting() -> Bool {
        adapter.validateInvariantsForTesting()
    }
}
