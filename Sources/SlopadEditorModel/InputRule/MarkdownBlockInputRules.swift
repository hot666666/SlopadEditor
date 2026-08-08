import SlopadCoreModel

// MARK: - Markdown Block Input Rules

/// The block prefixes Slopad recognizes while typing.
///
/// Declared as data rather than as branches inside `EditorModel` so the syntax knowledge is
/// separable from the machinery that applies it. When `SlopadMarkdown` exists these move
/// there unchanged; nothing in `EditorInputRuleRunner` knows what a heading is.
package enum MarkdownBlockInputRules {
    /// Everything here closes on one of these, which is what makes the runner's gate cheap.
    private static let closingCharacters: Set<Character> = [" ", "`"]

    private static let fixed: [(marker: String, kind: BlockKind)] = [
        ("# ", .heading(level: .h1)),
        ("## ", .heading(level: .h2)),
        ("### ", .heading(level: .h3)),
        ("- ", .unorderedListItem),
        ("* ", .unorderedListItem),
        ("> ", .quote),
        ("[x] ", .todo(isChecked: true)),
        ("[X] ", .todo(isChecked: true)),
        ("[ ] ", .todo(isChecked: false)),
        ("[] ", .todo(isChecked: false)),
        ("```", .codeBlock(language: nil)),
    ]

    private static let orderedSuffix = ". "
    private static let orderedMaximumDigits = 9

    private static let scanLimit: Int = max(
        fixed.map(\.marker.count).max() ?? 0,
        orderedMaximumDigits + orderedSuffix.count
    )

    package static let all: [EditorInputRule] = [
        EditorInputRule(triggers: closingCharacters, scanLimit: scanLimit) { text, caretOffset in
            guard
                let caretIndex = text.index(
                    text.startIndex, offsetBy: caretOffset, limitedBy: text.endIndex)
            else { return nil }
            let marker = String(text[..<caretIndex])

            if let match = fixed.first(where: { $0.marker == marker }) {
                return .convertBlock(removing: TextRange(0, marker.count), to: match.kind)
            }
            guard let kind = orderedListKind(marker: marker) else { return nil }
            return .convertBlock(removing: TextRange(0, marker.count), to: kind)
        }
    ]

    private static func orderedListKind(marker: String) -> BlockKind? {
        guard marker.hasSuffix(orderedSuffix) else { return nil }
        let digits = marker.dropLast(orderedSuffix.count)
        guard
            !digits.isEmpty,
            digits.count <= orderedMaximumDigits,
            digits.allSatisfy(\.isNumber),
            let number = Int(digits)
        else { return nil }
        return .orderedListItem(restartNumber: number == 1 ? nil : number)
    }
}
