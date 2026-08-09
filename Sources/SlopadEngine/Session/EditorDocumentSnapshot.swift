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

/// A viewport-independent projection of the complete current canonical document.
///
/// `revision` is monotonically increasing for the lifetime of one `EditorSession`.
/// Its revision advances only for committed canonical document mutations. Selection,
/// layout, scrolling, and live IME updates do not advance it. During composition, `blocks`
/// includes the live canonical marked content while `revision` remains the last committed
/// value. A persistence host acts on `EditorUpdate.committedDocumentRevision` or commits
/// composition before saving. Reading this value never throws; unlike
/// `documentContextSnapshot()`, it remains available while composition is active.
///
/// Not `Codable`: `epoch` is meaningful only against a live Session in this process, and a
/// decodable epoch would defeat the staleness check it exists for. Hosts persist `blocks`,
/// which is `Codable`, through their own codec.
public struct EditorDocumentSnapshot: Hashable, Sendable {
    /// Identifies the Session this snapshot came from.
    ///
    /// Compare it against the epoch captured alongside an earlier revision before acting on
    /// that revision. `revision` alone cannot tell two Sessions apart because it restarts
    /// at zero whenever the Session is replaced.
    public let epoch: EditorSessionEpoch
    public let revision: EditorDocumentRevision
    /// Every canonical block in depth-first preorder.
    ///
    /// Parents always precede descendants. Array order is the canonical root and sibling
    /// order and must be preserved when reconstructing the tree.
    public let blocks: [EditorBlockInput]

    init(
        epoch: EditorSessionEpoch,
        revision: EditorDocumentRevision,
        blocks: [EditorBlockInput]
    ) {
        self.epoch = epoch
        self.revision = revision
        self.blocks = blocks
    }
}
