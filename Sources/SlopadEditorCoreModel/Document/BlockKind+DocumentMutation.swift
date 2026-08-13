// MARK: - BlockKind DocumentMutation

extension BlockKind {
    var continuationKindAfterSplit: BlockKind {
        switch self {
        case .unorderedListItem:
            .unorderedListItem

        case .orderedListItem:
            .orderedListItem(restartNumber: nil)

        case .todo:
            .todo(isChecked: false)

        default:
            .paragraph
        }
    }
}
