// MARK: - EditorBlockInput

public struct EditorBlockInput: Hashable, Codable, Sendable {
    public let id: BlockID
    public let parentID: BlockID?
    public let kind: BlockKind
    public let content: BlockContent

    public init(
        id: BlockID = BlockID(),
        parentID: BlockID? = nil,
        kind: BlockKind = .paragraph,
        content: BlockContent = BlockContent()
    ) {
        self.id = id
        self.parentID = parentID
        self.kind = kind
        self.content = content
    }
}
