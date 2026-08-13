// MARK: - BlockSelection

public struct BlockSelection: Hashable, Codable, Sendable {
    public var blockIDs: [BlockID]
    public var anchor: BlockID
    public var focus: BlockID

    public init(blockIDs: [BlockID], anchor: BlockID? = nil, focus: BlockID? = nil) {
        precondition(!blockIDs.isEmpty, "BlockSelection requires at least one block")
        precondition(
            Set(blockIDs).count == blockIDs.count,
            "BlockSelection blockIDs must be unique"
        )
        let resolvedAnchor = anchor ?? blockIDs.first!
        let resolvedFocus = focus ?? blockIDs.last!
        precondition(
            blockIDs.contains(resolvedAnchor),
            "BlockSelection anchor must be included in blockIDs"
        )
        precondition(
            blockIDs.contains(resolvedFocus),
            "BlockSelection focus must be included in blockIDs"
        )
        self.blockIDs = blockIDs
        self.anchor = resolvedAnchor
        self.focus = resolvedFocus
    }
}
