// MARK: - TextAffinity

/// Selects the upstream or downstream visual caret at a soft-line boundary.
///
/// Bidirectional traversal may need additional layout-derived inline context. That context
/// is transient backend/Session state and is not encoded in a canonical `TextPosition`.
public enum TextAffinity: String, Codable, Hashable, Sendable {
    /// Selects the upstream caret for an ambiguous logical offset.
    case upstream
    /// Selects the downstream caret for an ambiguous logical offset.
    case downstream
}
