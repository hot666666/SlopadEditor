import SlopadEditorCoreModel

// MARK: - Visible Selection Presentation

package struct EditorVisibleTextSelection: Sendable {
    package let blockID: BlockID
    package let range: TextRange
    package let rects: [EditorRect]
    package let blockTintRect: EditorRect?
}

package struct EditorSelectionPresentation: Sendable {
    package let visibleTextSelections: [EditorVisibleTextSelection]
    package let visibleBlockSelectionIDs: Set<BlockID>
    /// Union of only the visible, viewport-clipped selection geometry.
    package let visibleBounds: EditorRect?
    /// Visible geometry nearest the directional focus endpoint.
    package let focusRect: EditorRect?
    package let isAnchorVisible: Bool
    package let isFocusVisible: Bool

    package static let empty = EditorSelectionPresentation(
        visibleTextSelections: [],
        visibleBlockSelectionIDs: [],
        visibleBounds: nil,
        focusRect: nil,
        isAnchorVisible: false,
        isFocusVisible: false
    )
}
