// MARK: - BlockKind

public enum BlockKind: Hashable, Codable, Sendable {
    public enum HeadingLevel: Int, Hashable, Codable, Sendable, CaseIterable {
        case h1 = 1
        case h2 = 2
        case h3 = 3
    }

    case paragraph
    case heading(level: HeadingLevel)
    case unorderedListItem
    case orderedListItem(restartNumber: Int?)
    case quote
    case codeBlock(language: String?)
    case divider
    case todo(isChecked: Bool)
}
