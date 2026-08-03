import Foundation
import SlopadCoreModel

// MARK: - Editor Document Source

/// An opaque optimistic-concurrency token scoped to one `EditorSession` instance.
///
/// The token is intentionally not persistent. A host must obtain a fresh context after a
/// document commit, selection change, Session replacement, or composition lifecycle.
public struct EditorDocumentSource: Hashable, Sendable {
    let sessionEpoch: UUID
    let revision: EditorDocumentRevision
    let selection: EditorSelection

    init(
        sessionEpoch: UUID,
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
public struct EditorDocumentPatch: Hashable, Sendable {
    public let source: EditorDocumentSource
    public let replacementBlocks: [EditorBlockInput]
    public let selectionAfter: EditorSelection

    public init(
        source: EditorDocumentSource,
        replacementBlocks: [EditorBlockInput],
        selectionAfter: EditorSelection
    ) {
        self.source = source
        self.replacementBlocks = replacementBlocks
        self.selectionAfter = selectionAfter
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
}
