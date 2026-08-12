// MARK: - Block

package struct Block: Hashable, Codable, Sendable {
    package var id: BlockID
    package var parentID: BlockID?
    package var childIDs: [BlockID]
    package var kind: BlockKind
    package var content: BlockContent

    package init(
        id: BlockID = BlockID(),
        parentID: BlockID? = nil,
        childIDs: [BlockID] = [],
        kind: BlockKind = .paragraph,
        content: BlockContent = BlockContent()
    ) {
        self.id = id
        self.parentID = parentID
        self.childIDs = childIDs
        self.kind = kind
        self.content = content
    }
}
