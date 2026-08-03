// MARK: - Text Navigation Vocabulary

public enum TextNavigationDirection: Hashable, Sendable {
    /// Logical movement toward the beginning of text.
    case backward
    /// Logical movement toward the end of text.
    case forward
    /// Physical movement toward the visual left edge.
    case left
    /// Physical movement toward the visual right edge.
    case right
}

public enum TextNavigationDestination: Hashable, Sendable {
    case character
    case word
}

public enum TextLogicalBoundary: Hashable, Sendable {
    case start
    case end
}

/// Transient visual state returned by a text backend for the next navigation or caret query.
///
/// This value is derived from the current layout request. It is Session runtime state, not
/// canonical document or selection state, and must be discarded when its request no longer
/// matches.
public struct TextNavigationContext: Hashable, Sendable {
    /// Preferred position along the line's inline axis for the next navigation operation.
    public let preferredInlineOffset: Double
    /// Current visual caret position when it differs from the position's ordinary geometry.
    public let caretInlineOffset: Double?

    public init(
        preferredInlineOffset: Double,
        caretInlineOffset: Double? = nil
    ) {
        self.preferredInlineOffset = preferredInlineOffset
        self.caretInlineOffset = caretInlineOffset
    }
}

public struct TextHitTestResult: Hashable, Sendable {
    public let position: TextPosition
    public let navigationContext: TextNavigationContext?

    public init(
        position: TextPosition,
        navigationContext: TextNavigationContext? = nil
    ) {
        self.position = position
        self.navigationContext = navigationContext
    }
}

public enum TextNavigationResolution: Hashable, Sendable {
    case selection(TextSelection, context: TextNavigationContext?)
    case boundary(TextLogicalBoundary)
    case unchanged
}
