import SlopadCoreModel

// MARK: - EditorSessionActiveTextInputDescriptor

public struct EditorSessionActiveTextInputDescriptor: Sendable {
    public let selectedRange: TextRange
    public let focusOffset: Int
    public let focusAffinity: TextAffinity
    public let navigationContext: TextNavigationContext?
    public let renderDescriptor: EditorTextRenderDescriptor

    /// Where the caret sits, in document coordinates.
    ///
    /// Resolved here rather than by the platform adapter so a host draws what the Session
    /// already knows instead of asking the text backend itself. Without this every adapter
    /// re-derives the same three steps — local caret rect, text frame, subtract to convert —
    /// and needs the geometry contract to do it.
    public let caretRect: EditorRect?

    /// The selection highlight, in document coordinates. Empty when the selection is a caret.
    public let selectionRects: [EditorRect]

    init(
        selectedRange: TextRange,
        focusOffset: Int? = nil,
        focusAffinity: TextAffinity = .downstream,
        navigationContext: TextNavigationContext? = nil,
        renderDescriptor: EditorTextRenderDescriptor,
        caretRect: EditorRect? = nil,
        selectionRects: [EditorRect] = []
    ) {
        self.selectedRange = selectedRange
        self.focusOffset = focusOffset ?? selectedRange.upperBound
        self.focusAffinity = focusAffinity
        self.navigationContext = navigationContext
        self.renderDescriptor = renderDescriptor
        self.caretRect = caretRect
        self.selectionRects = selectionRects
    }
}
