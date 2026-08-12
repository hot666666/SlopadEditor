import SlopadCoreModel

// MARK: - BlockLayoutChangeSet

struct BlockLayoutChangeSet {
    var removedBlockIDs: [BlockID] = []
    var insertedBlockIDs: [BlockID] = []
    var movedBlockIDs: [BlockID] = []
    var updatedBlockIDs: Set<BlockID> = []
}
