// MARK: - TextComposition

public struct TextComposition: Hashable, Sendable {
    public let blockID: BlockID
    public let replacementRange: TextRange
    public let text: String

    public static func == (lhs: TextComposition, rhs: TextComposition) -> Bool {
        lhs.blockID == rhs.blockID
            && lhs.replacementRange == rhs.replacementRange
            && lhs.text == rhs.text
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(blockID)
        hasher.combine(replacementRange)
        hasher.combine(text)
    }

    // MARK: - Package State

    let revision: Int

    package init(blockID: BlockID, replacementRange: TextRange, text: String, revision: Int) {
        self.blockID = blockID
        self.replacementRange = replacementRange
        self.text = text
        self.revision = revision
    }

    package var compositionRevision: Int {
        revision
    }
}
