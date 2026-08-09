import SlopadCoreModel

// MARK: - Visible Selection Presentation

package struct EditorVisibleTextSelection: Sendable {
    package let blockID: BlockID
    package let range: TextRange
    package let rects: [EditorRect]
    package let blockTintRect: EditorRect?
}

package struct EditorSelectionPresentation: Sendable {
    package let visibleTextSelections: [EditorVisibleTextSelection]

    package static let empty = EditorSelectionPresentation(visibleTextSelections: [])
}
