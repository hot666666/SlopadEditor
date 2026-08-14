import Foundation
import SlopadEditorCoreModel

struct ArchiveV1Block {
    let rawID: String
    let rawParentID: String?
    let kind: BlockKind
    let text: String
    let marks: [BlockContent.InlineMark]

    var id: BlockID { BlockID(rawID) }

    func makeBlockInput() throws(CanonicalBlockContentValidationError) -> EditorBlockInput {
        let content = try BlockContent(validatingCanonicalText: text, marks: marks)
        return EditorBlockInput(
            id: id,
            parentID: rawParentID.map { BlockID($0) },
            kind: kind,
            content: content
        )
    }
}

enum ArchiveV1Decoder {
    static func decodeBlocks(
        _ value: StrictJSONValue,
        allowsCustomBlocks: Bool = false
    ) throws(StrictJSONError) -> [ArchiveV1Block] {
        guard case .array(let values) = value else { throw .malformed }
        var blocks: [ArchiveV1Block] = []
        blocks.reserveCapacity(values.count)
        for value in values {
            blocks.append(try decodeBlock(value, allowsCustomBlocks: allowsCustomBlocks))
        }
        return blocks
    }

    private static func decodeBlock(
        _ value: StrictJSONValue,
        allowsCustomBlocks: Bool
    ) throws(StrictJSONError) -> ArchiveV1Block {
        let object = try value.exactObject(keys: ["id", "parentID", "kind", "content"])
        let id = try string(object.required("id"))
        let parentID = try nullableString(object.required("parentID"))
        let kind = try decodeKind(
            object.required("kind"),
            allowsCustomBlocks: allowsCustomBlocks
        )
        let (text, marks) = try decodeContent(object.required("content"))
        return ArchiveV1Block(
            rawID: id,
            rawParentID: parentID,
            kind: kind,
            text: text,
            marks: marks
        )
    }

    private static func decodeKind(
        _ value: StrictJSONValue,
        allowsCustomBlocks: Bool
    ) throws(StrictJSONError) -> BlockKind {
        guard case .object(let object) = value else { throw .malformed }
        let type = try string(object.required("type"))
        switch type {
        case "paragraph":
            try requireKeys(object, ["type"])
            return .paragraph
        case "heading":
            try requireKeys(object, ["type", "level"])
            let levelValue = try integer(object.required("level"))
            guard let level = BlockKind.HeadingLevel(rawValue: levelValue) else {
                throw StrictJSONError.malformed
            }
            return .heading(level: level)
        case "unorderedListItem":
            try requireKeys(object, ["type"])
            return .unorderedListItem
        case "orderedListItem":
            try requireKeys(object, ["type", "restartNumber"])
            return .orderedListItem(
                restartNumber: try nullableInteger(object.required("restartNumber"))
            )
        case "quote":
            try requireKeys(object, ["type"])
            return .quote
        case "codeBlock":
            try requireKeys(object, ["type", "language"])
            return .codeBlock(language: try nullableString(object.required("language")))
        case "divider":
            try requireKeys(object, ["type"])
            return .divider
        case "todo":
            try requireKeys(object, ["type", "isChecked"])
            return .todo(isChecked: try boolean(object.required("isChecked")))
        case "custom":
            // Only V2 admits this. A V1 archive naming it was not written by a V1 writer,
            // so it is malformed rather than a document to salvage.
            guard allowsCustomBlocks else { throw StrictJSONError.malformed }
            try requireKeys(object, ["type", "typeID", "version", "payload"])
            let typeID = try string(object.required("typeID"))
            let version = try integer(object.required("version"))
            let encodedPayload = try string(object.required("payload"))
            // Strict decoding: a payload that is not exact base64 fails the archive rather
            // than reaching the host as silently different bytes.
            guard
                let payload = Data(
                    base64Encoded: encodedPayload,
                    options: []
                )
            else { throw StrictJSONError.malformed }
            return .custom(typeID: typeID, version: version, payload: payload)
        default:
            throw .malformed
        }
    }

    private static func decodeContent(
        _ value: StrictJSONValue
    ) throws(StrictJSONError) -> (String, [BlockContent.InlineMark]) {
        let object = try value.exactObject(keys: ["text", "marks"])
        let text = try string(object.required("text"))
        guard case .array(let rawMarks) = try object.required("marks") else {
            throw .malformed
        }
        let textLength = text.count
        var marks: [BlockContent.InlineMark] = []
        marks.reserveCapacity(rawMarks.count)
        for rawMark in rawMarks {
            let mark = try rawMark.exactObject(keys: ["kind", "range"])
            let kind = try decodeMarkKind(mark.required("kind"))
            let range = try mark.required("range").exactObject(
                keys: ["lowerBound", "upperBound"]
            )
            let lowerBound = try integer(range.required("lowerBound"))
            let upperBound = try integer(range.required("upperBound"))
            guard lowerBound >= 0, lowerBound < upperBound, upperBound <= textLength else {
                throw StrictJSONError.malformed
            }
            marks.append(
                BlockContent.InlineMark(
                    kind: kind,
                    range: TextRange(lowerBound, upperBound)
                )
            )
        }
        return (text, marks)
    }

    private static func decodeMarkKind(
        _ value: StrictJSONValue
    ) throws(StrictJSONError) -> BlockContent.InlineMark.Kind {
        guard case .object(let object) = value else { throw .malformed }
        let type = try string(object.required("type"))
        switch type {
        case "strong":
            try requireKeys(object, ["type"])
            return .strong
        case "emphasis":
            try requireKeys(object, ["type"])
            return .emphasis
        case "code":
            try requireKeys(object, ["type"])
            return .code
        case "strikethrough":
            try requireKeys(object, ["type"])
            return .strikethrough
        case "link":
            try requireKeys(object, ["type", "destination"])
            return .link(destination: try string(object.required("destination")))
        default:
            throw .malformed
        }
    }

    private static func requireKeys(
        _ object: StrictJSONObject,
        _ expected: Set<String>
    ) throws(StrictJSONError) {
        guard object.keys == expected else { throw .malformed }
    }

    private static func string(_ value: StrictJSONValue) throws(StrictJSONError) -> String {
        guard case .string(let value) = value else { throw .malformed }
        return value
    }

    private static func nullableString(
        _ value: StrictJSONValue
    ) throws(StrictJSONError) -> String? {
        if case .null = value { return nil }
        return try string(value)
    }

    private static func boolean(_ value: StrictJSONValue) throws(StrictJSONError) -> Bool {
        guard case .bool(let value) = value else { throw .malformed }
        return value
    }

    private static func integer(_ value: StrictJSONValue) throws(StrictJSONError) -> Int {
        guard case .number(let token) = value, let value = Int(token) else { throw .malformed }
        return value
    }

    private static func nullableInteger(
        _ value: StrictJSONValue
    ) throws(StrictJSONError) -> Int? {
        if case .null = value { return nil }
        return try integer(value)
    }
}
