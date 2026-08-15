import Foundation
public import SlopadEditorCoreModel

public typealias BlockID = SlopadEditorCoreModel.BlockID
public typealias BlockKind = SlopadEditorCoreModel.BlockKind
public typealias BlockContent = SlopadEditorCoreModel.BlockContent
public typealias TextRange = SlopadEditorCoreModel.TextRange
public typealias EditorBlockInput = SlopadEditorCoreModel.EditorBlockInput

/// A synchronous, stateless conversion between canonical block inputs and SlopadEditor's native archive.
public enum SlopadEditorArchive {
    public static func encode(
        _ blocks: [EditorBlockInput]
    ) throws(SlopadEditorArchiveEncodingError) -> Data {
        try encode(blocks, onCanonicalValidation: {})
    }

    static func encodeForTesting(
        _ blocks: [EditorBlockInput],
        onCanonicalValidation: () -> Void
    ) throws(SlopadEditorArchiveEncodingError) -> Data {
        try encode(blocks, onCanonicalValidation: onCanonicalValidation)
    }

    private static func encode(
        _ blocks: [EditorBlockInput],
        onCanonicalValidation: () -> Void
    ) throws(SlopadEditorArchiveEncodingError) -> Data {
        // A document earns V2 only by containing something V1 cannot express. Emitting V1
        // whenever possible keeps every archive written so far readable by readers that
        // predate custom blocks; bumping unconditionally would strand them for a feature
        // the document does not use.
        let formatVersion = blocks.contains { $0.kind.isCustom } ? 2 : 1

        do {
            try ArchiveAdmissionPreflight.validate(blocks, formatVersion: formatVersion)
        } catch {
            switch error {
            case .exceeded(let blockID):
                throw .canonicalInvariant(.invalidContent(blockID: blockID))
            }
        }

        onCanonicalValidation()
        do {
            try CanonicalDocumentInput.validate(blocks)
        } catch {
            throw .canonicalInvariant(SlopadEditorArchiveCanonicalInvariant(error))
        }

        do {
            return try ArchiveEncoder.encode(blocks, formatVersion: formatVersion)
        } catch {
            switch error {
            case .exceeded(let blockID):
                throw .canonicalInvariant(.invalidContent(blockID: blockID))
            }
        }
    }

    public static func decode(
        _ data: Data
    ) throws(SlopadEditorArchiveDecodingError) -> [EditorBlockInput] {
        let root: StrictJSONValue
        do {
            root = try StrictJSONParser.parse(data)
        } catch {
            throw .malformedData
        }

        let envelope: StrictJSONObject
        do {
            envelope = try root.exactObject(keys: ["formatVersion", "blocks"])
        } catch {
            throw .malformedData
        }

        let version: Int
        do {
            version = try envelope.requiredInteger("formatVersion")
        } catch {
            throw .malformedData
        }

        switch version {
        case 1:
            return try decodeBlocks(envelope, allowsCustomBlocks: false)
        case 2:
            return try decodeBlocks(envelope, allowsCustomBlocks: true)
        case 3...:
            throw .unsupportedFutureVersion(found: version, latestSupported: 2)
        default:
            throw .unsupportedPastVersion(found: version, earliestSupported: 1)
        }
    }

    /// Decodes the block array for a known envelope version.
    ///
    /// The two versions share every rule but one: only V2 admits a custom block. A V1
    /// archive carrying one is malformed rather than tolerated, because a V1 writer could
    /// not have produced it and guessing at intent is how a format quietly widens.
    private static func decodeBlocks(
        _ envelope: StrictJSONObject,
        allowsCustomBlocks: Bool
    ) throws(SlopadEditorArchiveDecodingError) -> [EditorBlockInput] {
        let rawBlocks: [ArchiveBlock]
        do {
            rawBlocks = try ArchiveDecoder.decodeBlocks(
                envelope.required("blocks"),
                allowsCustomBlocks: allowsCustomBlocks
            )
        } catch {
            throw .malformedData
        }

        var blocks: [EditorBlockInput] = []
        blocks.reserveCapacity(rawBlocks.count)
        for rawBlock in rawBlocks {
            do {
                blocks.append(try rawBlock.makeBlockInput())
            } catch {
                throw .canonicalInvariant(.invalidContent(blockID: rawBlock.id))
            }
        }

        do {
            try CanonicalDocumentInput.validate(blocks)
        } catch {
            throw .canonicalInvariant(SlopadEditorArchiveCanonicalInvariant(error))
        }
        return blocks
    }
}

public enum SlopadEditorArchiveEncodingError: Error, Hashable, Sendable {
    case canonicalInvariant(SlopadEditorArchiveCanonicalInvariant)
}

public enum SlopadEditorArchiveDecodingError: Error, Hashable, Sendable {
    case malformedData
    case unsupportedFutureVersion(found: Int, latestSupported: Int)
    case unsupportedPastVersion(found: Int, earliestSupported: Int)
    case canonicalInvariant(SlopadEditorArchiveCanonicalInvariant)
}

public enum SlopadEditorArchiveCanonicalInvariant: Hashable, Sendable {
    case emptyDocument
    case duplicateBlockID(BlockID)
    case invalidContent(blockID: BlockID)
    case missingParent(blockID: BlockID, parentID: BlockID)
    case cycleDetected(BlockID)
    case noncanonicalDepthFirstOrder
    case customTypeIDEmpty(BlockID)
    case customPayloadTooLarge(BlockID)
    case customBlockCarriesText(BlockID)
    case customBlockHasChildren(BlockID)
}

extension SlopadEditorArchiveCanonicalInvariant {
    fileprivate init(_ error: CanonicalDocumentInputValidationError) {
        switch error {
        case .emptyDocument:
            self = .emptyDocument
        case .duplicateBlockID(let blockID):
            self = .duplicateBlockID(blockID)
        case .invalidContent(let blockID):
            self = .invalidContent(blockID: blockID)
        case .missingParent(let blockID, let parentID):
            self = .missingParent(blockID: blockID, parentID: parentID)
        case .cycleDetected(let blockID):
            self = .cycleDetected(blockID)
        case .noncanonicalDepthFirstOrder:
            self = .noncanonicalDepthFirstOrder
        case .customTypeIDEmpty(let blockID):
            self = .customTypeIDEmpty(blockID)
        case .customPayloadTooLarge(let blockID):
            self = .customPayloadTooLarge(blockID)
        case .customBlockCarriesText(let blockID):
            self = .customBlockCarriesText(blockID)
        case .customBlockHasChildren(let blockID):
            self = .customBlockHasChildren(blockID)
        }
    }
}
