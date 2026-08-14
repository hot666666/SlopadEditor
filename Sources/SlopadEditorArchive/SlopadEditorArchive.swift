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
        // V1's wire vocabulary is closed and has no representation for a host payload.
        // Rejecting here, before any byte is produced, keeps the failure whole: a caller
        // never receives an archive whose custom blocks were silently dropped. Carrying
        // them is a V2 change, not a V1 extension.
        if let customBlock = blocks.first(where: { $0.kind.isCustom }) {
            throw .unsupportedCustomBlock(blockID: customBlock.id)
        }

        do {
            try ArchiveV1AdmissionPreflight.validate(blocks)
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
            return try ArchiveV1Encoder.encode(blocks)
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
            return try decodeV1(envelope)
        case 2...:
            throw .unsupportedFutureVersion(found: version, latestSupported: 1)
        default:
            throw .unsupportedPastVersion(found: version, earliestSupported: 1)
        }
    }

    private static func decodeV1(
        _ envelope: StrictJSONObject
    ) throws(SlopadEditorArchiveDecodingError) -> [EditorBlockInput] {
        let rawBlocks: [ArchiveV1Block]
        do {
            rawBlocks = try ArchiveV1Decoder.decodeBlocks(envelope.required("blocks"))
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
    /// The document contains a host-defined custom block, which the V1 wire format cannot
    /// represent. No bytes are produced.
    case unsupportedCustomBlock(blockID: BlockID)
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
