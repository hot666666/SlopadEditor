import Foundation

// MARK: - BlockKind

public enum BlockKind: Hashable, Codable, Sendable {
    public enum HeadingLevel: Int, Hashable, Codable, Sendable, CaseIterable {
        case h1 = 1
        case h2 = 2
        case h3 = 3
    }

    case paragraph
    case heading(level: HeadingLevel)
    case unorderedListItem
    case orderedListItem(restartNumber: Int?)
    case quote
    case codeBlock(language: String?)
    case divider
    case todo(isChecked: Bool)

    /// A block whose meaning belongs to the embedding app rather than to the editor.
    ///
    /// The editor validates identity, leaf-ness, and size. It never decodes `payload` and
    /// never renders the block's body; a host provider registered on the editor instance
    /// supplies both the view and the height.
    ///
    /// The payload rides on the kind rather than on `BlockContent` because block
    /// measurement is cached on a key built from `kind`, text, and marks. A payload the key
    /// could not see would return a stale height after an edit — the exact failure the
    /// value-derived key exists to make impossible.
    case custom(typeID: String, version: Int, payload: Data)
}

// MARK: - Custom Block Limits

extension BlockKind {
    /// Per-block ceiling for an opaque host payload.
    ///
    /// One number is shared by the archive codec, the structured clipboard, and
    /// reviewed-patch validation. Three separate limits would produce a document that saves
    /// but cannot be copied, or that a patch admits and persistence then rejects.
    ///
    /// It is deliberately generous for the reference case — a block displaying an
    /// app-owned record needs hundreds of bytes — while keeping a large document well
    /// inside the archive's own wire budget.
    public static let customPayloadByteLimit = 64 * 1_024

    /// Whether this kind is a host-defined custom block, ignoring its associated values.
    public var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}
