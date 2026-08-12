// MARK: - BlockHitTestResult

public struct BlockHitTestResult: Hashable, Sendable {
    public let blockID: BlockID
    public let region: BlockHitRegion
    public let textPosition: TextPosition?

    package init(blockID: BlockID, region: BlockHitRegion, textPosition: TextPosition? = nil) {
        self.blockID = blockID
        self.region = region
        self.textPosition = textPosition
    }
}
