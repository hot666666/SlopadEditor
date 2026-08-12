import SlopadCoreModel

// MARK: - VisibleBlock

struct VisibleBlock {
    let blockID: BlockID
    let depth: Int
    let parentID: BlockID?

    init(blockID: BlockID, depth: Int, parentID: BlockID?) {
        self.blockID = blockID
        self.depth = depth
        self.parentID = parentID
    }
}
