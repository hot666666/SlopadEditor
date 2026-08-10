import SlopadCoreModel

enum ArchiveV1EncodingBudgetError: Error, Equatable {
    case exceeded(blockID: BlockID)
}

/// Allocation-bounded admission over caller-owned values. It runs before Core canonical
/// validation so hostile collection sizes cannot force its document maps or traversals.
enum ArchiveV1AdmissionPreflight {
    static func validate(
        _ blocks: [EditorBlockInput],
        budget: ArchiveWireBudget = .v1
    ) throws(ArchiveV1EncodingBudgetError) {
        var tracker = ArchiveWireBudgetTracker(budget: budget)
        do {
            try tracker.consumeArchiveBytes("{\"formatVersion\":1,\"blocks\":[".utf8.count)
            try tracker.consumeObject(memberCount: 2, decodedKeyBytes: 19)
            try tracker.consumeScalarValue()
            try tracker.consumeArray()
        } catch {
            throw .exceeded(blockID: blocks.first?.id ?? BlockID(""))
        }

        for (index, block) in blocks.enumerated() {
            do {
                if index > 0 { try tracker.consumeArchiveBytes(1) }
                try tracker.consumeArrayElement()
                try consume(block, with: &tracker)
            } catch {
                throw .exceeded(blockID: block.id)
            }
        }

        do {
            try tracker.consumeArchiveBytes(2)
        } catch {
            throw .exceeded(blockID: blocks.last?.id ?? BlockID(""))
        }
    }

    private static func consume(
        _ block: EditorBlockInput,
        with tracker: inout ArchiveWireBudgetTracker
    ) throws(StrictJSONError) {
        try tracker.consumeObject(memberCount: 4, decodedKeyBytes: 21)
        try tracker.consumeArchiveBytes("{\"id\":".utf8.count)
        try consume(block.id.rawValue, with: &tracker)
        try tracker.consumeArchiveBytes(",\"parentID\":".utf8.count)
        if let parentID = block.parentID {
            try consume(parentID.rawValue, with: &tracker)
        } else {
            try tracker.consumeScalarValue()
            try tracker.consumeArchiveBytes(4)
        }
        try tracker.consumeArchiveBytes(",\"kind\":".utf8.count)
        try consume(block.kind, with: &tracker)
        try tracker.consumeArchiveBytes(",\"content\":{\"text\":".utf8.count)
        try tracker.consumeObject(memberCount: 2, decodedKeyBytes: 9)
        try consume(block.content.text, with: &tracker)
        try tracker.consumeArchiveBytes(",\"marks\":[".utf8.count)
        try tracker.consumeArray()
        for (index, mark) in block.content.marks.enumerated() {
            if index > 0 { try tracker.consumeArchiveBytes(1) }
            try tracker.consumeArrayElement()
            try consume(mark, with: &tracker)
        }
        try tracker.consumeArchiveBytes(3)
    }

    private static func consume(
        _ kind: BlockKind,
        with tracker: inout ArchiveWireBudgetTracker
    ) throws(StrictJSONError) {
        switch kind {
        case .paragraph:
            try consumeTaggedObject(type: "paragraph", with: &tracker)
        case .heading(let level):
            try consumeAssociatedObject(
                type: "heading", key: "level", valueBytes: String(level.rawValue).utf8.count,
                with: &tracker
            )
        case .unorderedListItem:
            try consumeTaggedObject(type: "unorderedListItem", with: &tracker)
        case .orderedListItem(let restartNumber):
            let valueBytes = restartNumber.map { String($0).utf8.count } ?? 4
            try consumeAssociatedObject(
                type: "orderedListItem", key: "restartNumber", valueBytes: valueBytes,
                with: &tracker
            )
        case .quote:
            try consumeTaggedObject(type: "quote", with: &tracker)
        case .codeBlock(let language):
            try tracker.consumeObject(memberCount: 2, decodedKeyBytes: 12)
            try tracker.consumeArchiveBytes("{\"type\":".utf8.count)
            try consume("codeBlock", with: &tracker)
            try tracker.consumeArchiveBytes(",\"language\":".utf8.count)
            if let language {
                try consume(language, with: &tracker)
            } else {
                try tracker.consumeScalarValue()
                try tracker.consumeArchiveBytes(4)
            }
            try tracker.consumeArchiveBytes(1)
        case .divider:
            try consumeTaggedObject(type: "divider", with: &tracker)
        case .todo(let isChecked):
            try consumeAssociatedObject(
                type: "todo", key: "isChecked", valueBytes: isChecked ? 4 : 5,
                with: &tracker
            )
        }
    }

    private static func consume(
        _ mark: BlockContent.InlineMark,
        with tracker: inout ArchiveWireBudgetTracker
    ) throws(StrictJSONError) {
        try tracker.consumeObject(memberCount: 2, decodedKeyBytes: 9)
        try tracker.consumeArchiveBytes("{\"kind\":".utf8.count)
        switch mark.kind {
        case .strong:
            try consumeTaggedObject(type: "strong", with: &tracker)
        case .emphasis:
            try consumeTaggedObject(type: "emphasis", with: &tracker)
        case .code:
            try consumeTaggedObject(type: "code", with: &tracker)
        case .strikethrough:
            try consumeTaggedObject(type: "strikethrough", with: &tracker)
        case .link(let destination):
            try tracker.consumeObject(memberCount: 2, decodedKeyBytes: 15)
            try tracker.consumeArchiveBytes("{\"type\":".utf8.count)
            try consume("link", with: &tracker)
            try tracker.consumeArchiveBytes(",\"destination\":".utf8.count)
            try consume(destination, with: &tracker)
            try tracker.consumeArchiveBytes(1)
        }
        try tracker.consumeArchiveBytes(",\"range\":{\"lowerBound\":".utf8.count)
        try tracker.consumeObject(memberCount: 2, decodedKeyBytes: 20)
        try tracker.consumeScalarValue()
        try tracker.consumeArchiveBytes(String(mark.range.lowerBound).utf8.count)
        try tracker.consumeArchiveBytes(",\"upperBound\":".utf8.count)
        try tracker.consumeScalarValue()
        try tracker.consumeArchiveBytes(String(mark.range.upperBound).utf8.count)
        try tracker.consumeArchiveBytes(2)
    }

    private static func consumeTaggedObject(
        type: String,
        with tracker: inout ArchiveWireBudgetTracker
    ) throws(StrictJSONError) {
        try tracker.consumeObject(memberCount: 1, decodedKeyBytes: 4)
        try tracker.consumeArchiveBytes("{\"type\":".utf8.count)
        try consume(type, with: &tracker)
        try tracker.consumeArchiveBytes(1)
    }

    private static func consumeAssociatedObject(
        type: String,
        key: String,
        valueBytes: Int,
        with tracker: inout ArchiveWireBudgetTracker
    ) throws(StrictJSONError) {
        try tracker.consumeObject(memberCount: 2, decodedKeyBytes: 4 + key.utf8.count)
        try tracker.consumeArchiveBytes("{\"type\":".utf8.count)
        try consume(type, with: &tracker)
        try tracker.consumeArchiveBytes(key.utf8.count + 4)
        try tracker.consumeScalarValue()
        try tracker.consumeArchiveBytes(valueBytes)
        try tracker.consumeArchiveBytes(1)
    }

    private static func consume(
        _ string: String,
        with tracker: inout ArchiveWireBudgetTracker
    ) throws(StrictJSONError) {
        try tracker.consumeString(decodedUTF8Bytes: string.utf8.count)
        try tracker.consumeArchiveBytes(2)
        for scalar in string.unicodeScalars {
            let encodedBytes: Int
            switch scalar.value {
            case 0x22, 0x5C, 0x08, 0x0C, 0x0A, 0x0D, 0x09:
                encodedBytes = 2
            case 0x00...0x1F:
                encodedBytes = 6
            default:
                encodedBytes = scalar.utf8.count
            }
            try tracker.consumeArchiveBytes(encodedBytes)
        }
    }
}
