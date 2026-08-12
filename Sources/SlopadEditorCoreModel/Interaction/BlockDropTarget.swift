// MARK: - BlockDropTarget

public struct BlockDropTarget: Hashable, Sendable {
    public enum Placement: Hashable, Sendable {
        case before
        case after
    }

    public let blockID: BlockID
    public let placement: Placement

    package init(blockID: BlockID, placement: Placement) {
        self.blockID = blockID
        self.placement = placement
    }
}
