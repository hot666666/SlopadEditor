// MARK: - TextSelection

public struct TextSelection: Hashable, Codable, Sendable {
    public var anchor: TextPosition
    public var focus: TextPosition

    public init(anchor: TextPosition, focus: TextPosition) {
        self.anchor = anchor
        self.focus = focus
    }

    public var isSingleBlock: Bool {
        anchor.blockID == focus.blockID
    }

    public var rangeInSingleBlock: TextRange? {
        guard isSingleBlock else { return nil }
        return TextRange(min(anchor.offset, focus.offset), max(anchor.offset, focus.offset))
    }
}
