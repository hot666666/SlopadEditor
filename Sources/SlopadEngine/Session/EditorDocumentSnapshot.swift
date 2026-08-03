import SlopadCoreModel

// MARK: - EditorDocumentRevision

/// A monotonically increasing committed content-or-structure token scoped to one
/// `EditorSession`.
///
/// Replacing the Session starts a new revision sequence at zero. This value is not a host
/// database or storage revision.
public struct EditorDocumentRevision: RawRepresentable, Hashable, Codable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - EditorDocumentSnapshot

/// A viewport-independent projection of the complete committed canonical document.
///
/// `revision` is monotonically increasing for the lifetime of one `EditorSession`.
/// Its revision advances only for committed canonical document mutations. Selection,
/// layout, scrolling, and live IME composition do not advance it.
public struct EditorDocumentSnapshot: Hashable, Codable, Sendable {
    public let revision: EditorDocumentRevision
    /// Every canonical block in depth-first preorder.
    ///
    /// Parents always precede descendants. Array order is the canonical root and sibling
    /// order and must be preserved when reconstructing the tree.
    public let blocks: [EditorBlockInput]

    init(revision: EditorDocumentRevision, blocks: [EditorBlockInput]) {
        self.revision = revision
        self.blocks = blocks
    }
}
