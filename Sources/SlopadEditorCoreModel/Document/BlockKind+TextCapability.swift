// MARK: - BlockKind Text Capability

extension BlockKind {
    /// Whether canonical inline text and marks are meaningful for this block kind.
    ///
    /// A divider is atomic. It participates in structural command spans but never becomes
    /// an inline-formatting target merely because malformed or legacy input carried text.
    package var isTextCapable: Bool {
        switch self {
        case .divider:
            false
        case .paragraph, .heading, .unorderedListItem, .orderedListItem, .quote, .codeBlock,
            .todo:
            true
        }
    }
}
