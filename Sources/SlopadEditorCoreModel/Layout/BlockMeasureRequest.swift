// MARK: - BlockMeasureRequest

public struct BlockMeasureRequest: Hashable, Sendable {
    public let blockID: BlockID
    public let text: String
    public let kind: BlockKind
    public let inlineRuns: [BlockContent.InlineRun]
    public let availableWidth: Double
    public let depth: Int

    public init(
        blockID: BlockID,
        text: String,
        kind: BlockKind,
        inlineRuns: [BlockContent.InlineRun] = [],
        availableWidth: Double,
        depth: Int
    ) {
        self.blockID = blockID
        self.text = text
        self.kind = kind
        self.inlineRuns = inlineRuns
        self.availableWidth = availableWidth
        self.depth = depth
    }

    package init(
        block: Block,
        depth: Int,
        availableWidth: Double
    ) {
        self.init(
            blockID: block.id,
            text: block.content.text,
            kind: block.kind,
            inlineRuns: block.content.inlineRuns,
            availableWidth: availableWidth,
            depth: depth
        )
    }
}
