// MARK: - EditorSelection

public enum EditorSelection: Hashable, Codable, Sendable {
    case inactive
    case caret(TextPosition)
    case text(TextSelection)
    case blocks(BlockSelection)

    public static func caret(blockID: BlockID, offset: Int) -> EditorSelection {
        .caret(TextPosition(blockID: blockID, offset: offset))
    }

    package func isCompatibleWithComposition(blockID: BlockID) -> Bool {
        switch self {
        case .inactive:
            return false

        case .caret(let position):
            return position.blockID == blockID

        case .text(let textSelection):
            return textSelection.isSingleBlock && textSelection.focus.blockID == blockID

        case .blocks:
            return false
        }
    }
}
