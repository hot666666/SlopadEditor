// MARK: - BlockKind Text Capability

extension BlockKind {
    /// Whether canonical inline text and marks are meaningful for this block kind.
    ///
    /// A divider is atomic. It participates in structural command spans but never becomes
    /// an inline-formatting target merely because malformed or legacy input carried text.
    ///
    /// A custom block is atomic for the same reason and one more: its content belongs to
    /// the host, so the editor has nothing to format. Canonical validation rejects a custom
    /// block that carries text or marks rather than silently ignoring them.
    package var isTextCapable: Bool {
        switch self {
        case .divider, .custom:
            false
        case .paragraph, .heading, .unorderedListItem, .orderedListItem, .quote, .codeBlock,
            .todo:
            true
        }
    }
}
