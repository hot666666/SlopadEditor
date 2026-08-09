// MARK: - Editor Clipboard Payload

/// Slopad's versioned, format-neutral clipboard representation.
///
/// The pasteboard adapter serializes this value at the edge. Canonical mutation still
/// happens in `EditorModel`; this payload is not a second document model.
public struct EditorClipboardPayload: Hashable, Codable, Sendable {
    public static let currentVersion = 1

    public enum Content: Hashable, Codable, Sendable {
        case textSlice(EditorClipboardTextSlice)
        case blockSubtrees(EditorClipboardBlockSubtrees)
    }

    public let version: Int
    public let content: Content

    public init(version: Int = currentVersion, content: Content) {
        self.version = version
        self.content = content
    }
}

/// A text-origin selection. Endpoint wrappers are always open: their text merges into the
/// destination edges even when an endpoint happened to be fully covered.
public struct EditorClipboardTextSlice: Hashable, Codable, Sendable {
    public let blocks: [EditorBlockInput]

    public init(blocks: [EditorBlockInput]) {
        self.blocks = blocks
    }
}

/// A structural selection containing complete, deduplicated roots and their subtrees.
public struct EditorClipboardBlockSubtrees: Hashable, Codable, Sendable {
    public let blocks: [EditorBlockInput]

    public init(blocks: [EditorBlockInput]) {
        self.blocks = blocks
    }
}

/// One copy operation writes the typed representation and its external plain-text fallback.
public struct EditorClipboardWritePlan: Hashable, Sendable {
    public let payload: EditorClipboardPayload
    public let plainText: String

    public init(payload: EditorClipboardPayload, plainText: String) {
        self.payload = payload
        self.plainText = plainText
    }
}
