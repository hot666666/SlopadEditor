import SlopadCoreModel

// MARK: - EditorSessionActiveTextInputDescriptor

public struct EditorSessionActiveTextInputDescriptor: Sendable {
    public let selectedRange: TextRange
    public let focusOffset: Int
    public let focusAffinity: TextAffinity
    public let navigationContext: TextNavigationContext?
    public let renderDescriptor: EditorTextRenderDescriptor

    init(
        selectedRange: TextRange,
        focusOffset: Int? = nil,
        focusAffinity: TextAffinity = .downstream,
        navigationContext: TextNavigationContext? = nil,
        renderDescriptor: EditorTextRenderDescriptor
    ) {
        self.selectedRange = selectedRange
        self.focusOffset = focusOffset ?? selectedRange.upperBound
        self.focusAffinity = focusAffinity
        self.navigationContext = navigationContext
        self.renderDescriptor = renderDescriptor
    }
}
