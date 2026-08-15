import Foundation
import SlopadEditorCoreModel

// MARK: - Editor Document Source

/// An opaque optimistic-concurrency token scoped to one `EditorSession` instance.
///
/// The token is intentionally not persistent. A host must obtain a fresh context after a
/// document commit, selection change, Session replacement, or composition lifecycle.
///
/// It shares the Session epoch with the persistence path but stays a strictly stronger
/// token: a patch also pins the exact revision and selection, because replacing a document
/// the caller no longer sees is a silent overwrite. Persistence needs only the epoch, so it
/// reads that one field from `EditorDocumentSnapshot` rather than weakening this token.
public struct EditorDocumentSource: Hashable, Sendable {
    let sessionEpoch: EditorSessionEpoch
    let revision: EditorDocumentRevision
    let selection: EditorSelection

    init(
        sessionEpoch: EditorSessionEpoch,
        revision: EditorDocumentRevision,
        selection: EditorSelection
    ) {
        self.sessionEpoch = sessionEpoch
        self.revision = revision
        self.selection = selection
    }
}

// MARK: - Selected Text

/// A Session-produced output projection. Hosts may encode it for review transport but
/// cannot construct or decode unchecked fragment values through the public API.
public struct EditorSelectedTextFragment: Hashable, Encodable, Sendable {
    public let blockID: BlockID
    public let parentID: BlockID?
    public let kind: BlockKind
    /// The selected range in the source block's grapheme coordinates.
    public let sourceRange: TextRange
    /// Sliced content whose inline mark ranges are relative to this fragment.
    public let content: BlockContent

    init(
        blockID: BlockID,
        parentID: BlockID?,
        kind: BlockKind,
        sourceRange: TextRange,
        content: BlockContent
    ) {
        self.blockID = blockID
        self.parentID = parentID
        self.kind = kind
        self.sourceRange = sourceRange
        self.content = content
    }
}

public struct EditorSelectedText: Hashable, Encodable, Sendable {
    /// Fragments in canonical block depth-first order, independent of selection direction.
    public let fragments: [EditorSelectedTextFragment]

    init(fragments: [EditorSelectedTextFragment]) {
        self.fragments = fragments
    }
}

// MARK: - Selected Block Subtrees

public struct EditorSelectedBlocks: Hashable, Encodable, Sendable {
    /// Canonically ordered selected roots after removing roots covered by an ancestor.
    public let rootBlockIDs: [BlockID]
    /// Every selected root and descendant in canonical depth-first order.
    public let blocks: [EditorBlockInput]

    init(rootBlockIDs: [BlockID], blocks: [EditorBlockInput]) {
        self.rootBlockIDs = rootBlockIDs
        self.blocks = blocks
    }
}

// MARK: - Selected Content

public enum EditorSelectedContent: Hashable, Encodable, Sendable {
    case none
    case text(EditorSelectedText)
    case blocks(EditorSelectedBlocks)
}

// MARK: - Document Context Snapshot

/// A Session-produced review-oriented canonical document context captured at one exact
/// Session state.
///
/// Unlike `EditorDocumentSnapshot`, this value includes selection and an opaque CAS source
/// for a later `applyDocumentPatch(_:)` call. It is not a persistence snapshot.
public struct EditorDocumentContextSnapshot: Hashable, Sendable {
    public let source: EditorDocumentSource
    public let document: EditorDocumentSnapshot
    public let selection: EditorSelection
    public let selectedContent: EditorSelectedContent

    init(
        source: EditorDocumentSource,
        document: EditorDocumentSnapshot,
        selection: EditorSelection,
        selectedContent: EditorSelectedContent
    ) {
        self.source = source
        self.document = document
        self.selection = selection
        self.selectedContent = selectedContent
    }
}

// MARK: - Document Patch

/// A canonical full-document post-image guarded by the exact source context.
/// What a patch is allowed to do to host-defined custom blocks.
///
/// The editor cannot decode a custom payload, so it cannot tell an intentional rewrite from
/// an accidental loss. A patch produced by round-tripping the document through a format that
/// has no representation for custom blocks would drop them silently, and the host would learn
/// about it when the data was already gone.
public enum EditorCustomBlockPatchPolicy: Hashable, Sendable {
    /// Every custom block present before the patch must still be present after it, with the
    /// same identity, type, version, and payload bytes.
    ///
    /// Position and parent are deliberately not compared. A patch that reorders paragraphs
    /// moves whatever sits between them, and rejecting that would fail almost every ordinary
    /// assistant patch — which would push callers to disable the policy entirely. A moved
    /// block is still reachable by `BlockID`; a deleted one is not.
    case preserve

    /// The caller asserts it understands the custom payloads in this document and may add,
    /// remove, retype, reversion, or rewrite them.
    ///
    /// This is not a general validation bypass. Every other canonical invariant still applies.
    case hostManaged
}

public struct EditorDocumentPatch: Hashable, Sendable {
    public let source: EditorDocumentSource
    public let replacementBlocks: [EditorBlockInput]
    public let selectionAfter: EditorSelection
    public let customBlockPolicy: EditorCustomBlockPatchPolicy

    public init(
        source: EditorDocumentSource,
        replacementBlocks: [EditorBlockInput],
        selectionAfter: EditorSelection,
        customBlockPolicy: EditorCustomBlockPatchPolicy = .preserve
    ) {
        self.source = source
        self.replacementBlocks = replacementBlocks
        self.selectionAfter = selectionAfter
        self.customBlockPolicy = customBlockPolicy
    }
}

// MARK: - Document Transaction Error

public enum EditorDocumentTransactionError: Error, Hashable, Sendable {
    case activeComposition
    case staleSource
    case emptyDocument
    case duplicateBlockID(BlockID)
    case invalidContent(blockID: BlockID)
    case missingParent(blockID: BlockID, parentID: BlockID)
    case cycleDetected(BlockID)
    case noncanonicalDepthFirstOrder
    case invalidSelection
    /// A custom block in the patch carried an empty `typeID`.
    case customTypeIDEmpty(BlockID)
    /// A custom block's payload exceeded ``BlockKind/customPayloadByteLimit``.
    case customPayloadTooLarge(BlockID)
    /// A custom block carried canonical text or inline marks, which it cannot own.
    case customBlockCarriesText(BlockID)
    /// A custom block had child blocks. First-version custom blocks are leaves.
    case customBlockHasChildren(BlockID)
    /// The patch dropped or altered a custom block under
    /// ``EditorCustomBlockPatchPolicy/preserve``.
    case customBlockNotPreserved(BlockID)
}
