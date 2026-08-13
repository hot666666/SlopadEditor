// MARK: - LineFragmentSnapshot

public struct LineFragmentSnapshot: Hashable, Sendable {
    public let blockID: BlockID
    public let range: TextRange
    public let rect: EditorRect

    public init(blockID: BlockID, range: TextRange, rect: EditorRect) {
        self.blockID = blockID
        self.range = range
        self.rect = rect
    }
}
