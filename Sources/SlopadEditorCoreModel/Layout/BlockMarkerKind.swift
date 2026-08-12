// MARK: - BlockMarkerKind

public enum BlockMarkerKind: Hashable, Sendable {
    case none
    case unorderedListItem
    case orderedListItem(number: Int)
    case todo(isChecked: Bool)
}
