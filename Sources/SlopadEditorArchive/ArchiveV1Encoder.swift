import Foundation
import SlopadEditorCoreModel

enum ArchiveV1Encoder {
    static func encode(
        _ blocks: [EditorBlockInput]
    ) throws(ArchiveV1EncodingBudgetError) -> Data {
        var output = LimitedArchiveOutput(budget: .v1)
        do {
            try output.append("{\"formatVersion\":1,\"blocks\":[")
        } catch {
            throw .exceeded(blockID: blocks[0].id)
        }
        for (index, block) in blocks.enumerated() {
            do {
                if index > 0 { try output.append(",") }
                try append(block, to: &output)
            } catch {
                throw .exceeded(blockID: block.id)
            }
        }
        do {
            try output.append("]}")
        } catch {
            throw .exceeded(blockID: blocks[blocks.count - 1].id)
        }
        return Data(output.value.utf8)
    }

    private static func append(
        _ block: EditorBlockInput,
        to output: inout LimitedArchiveOutput
    ) throws(StrictJSONError) {
        try output.append("{\"id\":")
        try appendJSONString(block.id.rawValue, to: &output)
        try output.append(",\"parentID\":")
        if let parentID = block.parentID {
            try appendJSONString(parentID.rawValue, to: &output)
        } else {
            try output.append("null")
        }
        try output.append(",\"kind\":")
        try append(block.kind, to: &output)
        try output.append(",\"content\":{\"text\":")
        try appendJSONString(block.content.text, to: &output)
        try output.append(",\"marks\":[")
        for (index, mark) in block.content.marks.enumerated() {
            if index > 0 { try output.append(",") }
            try append(mark, to: &output)
        }
        try output.append("]}}")
    }

    private static func append(
        _ kind: BlockKind,
        to output: inout LimitedArchiveOutput
    ) throws(StrictJSONError) {
        switch kind {
        case .paragraph:
            try output.append("{\"type\":\"paragraph\"}")
        case .heading(let level):
            try output.append("{\"type\":\"heading\",\"level\":\(level.rawValue)}")
        case .unorderedListItem:
            try output.append("{\"type\":\"unorderedListItem\"}")
        case .orderedListItem(let restartNumber):
            try output.append("{\"type\":\"orderedListItem\",\"restartNumber\":")
            try output.append(restartNumber.map(String.init) ?? "null")
            try output.append("}")
        case .quote:
            try output.append("{\"type\":\"quote\"}")
        case .codeBlock(let language):
            try output.append("{\"type\":\"codeBlock\",\"language\":")
            if let language {
                try appendJSONString(language, to: &output)
            } else {
                try output.append("null")
            }
            try output.append("}")
        case .divider:
            try output.append("{\"type\":\"divider\"}")
        case .todo(let isChecked):
            try output.append("{\"type\":\"todo\",\"isChecked\":")
            try output.append(isChecked ? "true" : "false")
            try output.append("}")
        }
    }

    private static func append(
        _ mark: BlockContent.InlineMark,
        to output: inout LimitedArchiveOutput
    ) throws(StrictJSONError) {
        try output.append("{\"kind\":")
        try append(mark.kind, to: &output)
        try output.append(
            ",\"range\":{\"lowerBound\":\(mark.range.lowerBound),\"upperBound\":\(mark.range.upperBound)}}"
        )
    }

    private static func append(
        _ kind: BlockContent.InlineMark.Kind,
        to output: inout LimitedArchiveOutput
    ) throws(StrictJSONError) {
        switch kind {
        case .strong:
            try output.append("{\"type\":\"strong\"}")
        case .emphasis:
            try output.append("{\"type\":\"emphasis\"}")
        case .code:
            try output.append("{\"type\":\"code\"}")
        case .strikethrough:
            try output.append("{\"type\":\"strikethrough\"}")
        case .link(let destination):
            try output.append("{\"type\":\"link\",\"destination\":")
            try appendJSONString(destination, to: &output)
            try output.append("}")
        }
    }

    private static func appendJSONString(
        _ string: String,
        to output: inout LimitedArchiveOutput
    ) throws(StrictJSONError) {
        let hex = Array("0123456789abcdef".utf8)
        try output.append("\"")
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22:
                try output.append("\\\"")
            case 0x5C:
                try output.append("\\\\")
            case 0x08:
                try output.append("\\b")
            case 0x0C:
                try output.append("\\f")
            case 0x0A:
                try output.append("\\n")
            case 0x0D:
                try output.append("\\r")
            case 0x09:
                try output.append("\\t")
            case 0x00...0x1F:
                let value = Int(scalar.value)
                try output.append("\\u00")
                try output.append(Character(UnicodeScalar(hex[(value >> 4) & 0xF])))
                try output.append(Character(UnicodeScalar(hex[value & 0xF])))
            default:
                try output.append(scalar)
            }
        }
        try output.append("\"")
    }
}

private struct LimitedArchiveOutput {
    private let maximumBytes: Int
    private(set) var value = ""
    private var byteCount = 0

    init(budget: ArchiveWireBudget) {
        maximumBytes = budget.maximumArchiveBytes
        value.reserveCapacity(min(maximumBytes, 1_024 * 1_024))
    }

    mutating func append(_ string: String) throws(StrictJSONError) {
        let addedBytes = string.utf8.count
        guard byteCount <= maximumBytes - addedBytes else { throw .malformed }
        value.append(string)
        byteCount += addedBytes
    }

    mutating func append(_ character: Character) throws(StrictJSONError) {
        try append(String(character))
    }

    mutating func append(_ scalar: UnicodeScalar) throws(StrictJSONError) {
        let addedBytes = scalar.utf8.count
        guard byteCount <= maximumBytes - addedBytes else { throw .malformed }
        value.unicodeScalars.append(scalar)
        byteCount += addedBytes
    }
}
