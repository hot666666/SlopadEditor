import SlopadAppKit

// MARK: - SlopadDocument

/// The document a host hands to ``SlopadEditor``, and the identity that decides when the
/// editor is showing a different one.
///
/// `id` is the whole reason this is a type rather than a bare `[EditorBlockInput]`. A
/// declarative host re-evaluates its body constantly, and blocks alone cannot distinguish
/// "the same document, re-sent" from "a different document". Treating every re-send as a
/// replacement destroys the caret, the undo stack, and any live IME composition.
///
/// Only blocks cross this boundary. Turning a stored format — a string, JSON, a file — into
/// blocks is the host's codec, and no string, format, or codec type appears in this API.
public struct SlopadDocument: Identifiable {
    /// Identifies which document this is. The editor replaces its content when this
    /// changes and leaves it alone when it does not.
    public let id: AnyHashable
    /// Every canonical block in depth-first preorder.
    public let blocks: [EditorBlockInput]

    public init(id: some Hashable, blocks: [EditorBlockInput]) {
        self.id = AnyHashable(id)
        self.blocks = blocks
    }
}
