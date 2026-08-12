import SlopadEditorCoreModel

private extension TextRange {
    func offset(by amount: Int) -> TextRange {
        TextRange(lowerBound + amount, upperBound + amount)
    }
}

// MARK: - Markdown Input Rules

/// Bounded Markdown patterns used while text is typed.
///
/// This lightweight target intentionally contains no parser dependency. `SlopadEditorMarkdown`
/// remains the opt-in whole-document codec; these rules only recognize a completed local
/// candidate after the editor-model runner has passed its trigger gate.
package enum MarkdownInputRules {
    package static let all: [EditorInputRule] = [
        blockPrefixes,
        inlineDelimiters,
        inlineCode,
        inlineLink,
    ]

    // MARK: Block prefixes

    private static let blockClosingCharacters: Set<Character> = [" ", "`"]
    private static let fixedBlockPrefixes: [(marker: String, kind: BlockKind)] = [
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

    private static let blockPrefixes = EditorInputRule(
        triggers: blockClosingCharacters,
        scanLimit: max(
            fixedBlockPrefixes.map(\.marker.count).max() ?? 0,
            orderedMaximumDigits + orderedSuffix.count
        )
    ) { candidate in
        let text = candidate.text
        let caretOffset = candidate.caretOffset
        guard let caret = text.index(text.startIndex, offsetBy: caretOffset, limitedBy: text.endIndex)
        else { return nil }
        let marker = String(text[..<caret])

        if let match = fixedBlockPrefixes.first(where: { $0.marker == marker }) {
            return .convertBlock(removing: TextRange(0, marker.count), to: match.kind)
        }
        guard let kind = orderedListKind(marker: marker) else { return nil }
        return .convertBlock(removing: TextRange(0, marker.count), to: kind)
    }

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

    // MARK: Inline delimiters

    /// One local candidate has enough room for two delimiters, a link destination, and a
    /// useful label while keeping triggered work independent of paragraph length.
    private static let inlineScanLimit = 512

    private static let inlineDelimiters = EditorInputRule(
        triggers: ["*", "_", "~"],
        scanLimit: inlineScanLimit,
        scanOrigin: .caret
    ) { candidate in
        let characters = Array(candidate.text)
        let caretOffset = candidate.caretOffset
        guard caretOffset > 0, unmatchedInlineCodeOpener(in: characters, before: caretOffset) == nil
        else { return nil }

        let delimiter = characters[caretOffset - 1]
        switch delimiter {
        case "*", "_":
            return emphasisOrStrong(
                in: characters, caretOffset: caretOffset, delimiter: delimiter, baseOffset: candidate.baseOffset)
        case "~":
            return strikethrough(in: characters, caretOffset: caretOffset, baseOffset: candidate.baseOffset)
        default:
            return nil
        }
    }

    private static let inlineCode = EditorInputRule(
        triggers: ["`"],
        scanLimit: inlineScanLimit,
        scanOrigin: .caret
    ) { candidate in
        let characters = Array(candidate.text)
        let caretOffset = candidate.caretOffset
        guard caretOffset > 0 else { return nil }
        let closing = delimiterRunEnding(at: caretOffset, in: characters, delimiter: "`")
        guard closing.length > 0, !isEscaped(closing.lowerBound, in: characters)
        else { return nil }
        guard let opening = nearestOpeningRun(
            before: closing.lowerBound,
            in: characters,
            delimiter: "`",
            length: closing.length,
            scanLimit: inlineScanLimit
        ) else { return nil }
        guard
            opening.upperBound < closing.lowerBound,
            !characters[opening.upperBound].isWhitespace,
            !characters[closing.lowerBound - 1].isWhitespace
        else { return nil }

        return .applyInline(
            marks: [.code],
            removing: [opening.offset(by: candidate.baseOffset), closing.offset(by: candidate.baseOffset)],
            marked: TextRange(opening.upperBound + candidate.baseOffset, closing.lowerBound + candidate.baseOffset)
        )
    }

    private static let inlineLink = EditorInputRule(
        triggers: [")"],
        scanLimit: inlineScanLimit,
        scanOrigin: .caret
    ) { candidate in
        let characters = Array(candidate.text)
        let caretOffset = candidate.caretOffset
        guard caretOffset > 0,
            unmatchedInlineCodeOpener(in: characters, before: caretOffset) == nil
        else { return nil }
        return link(in: characters, caretOffset: caretOffset, baseOffset: candidate.baseOffset)
    }

    // MARK: Matcher

    private static func emphasisOrStrong(
        in characters: [Character],
        caretOffset: Int,
        delimiter: Character,
        baseOffset: Int
    ) -> EditorInputRuleEffect? {
        let closing = delimiterRunEnding(at: caretOffset, in: characters, delimiter: delimiter)
        guard (1...3).contains(closing.length), !isEscaped(closing.lowerBound, in: characters)
        else { return nil }
        guard let opening = nearestOpeningRun(
            before: closing.lowerBound,
            in: characters,
            delimiter: delimiter,
            length: closing.length,
            scanLimit: inlineScanLimit
        ) else { return nil }
        guard isValidDelimiterPair(
            opening: opening,
            closing: closing,
            delimiter: delimiter,
            in: characters
        ) else { return nil }

        return .applyInline(
            marks: inlineMarks(forDelimiterRunLength: closing.length),
            removing: [opening.offset(by: baseOffset), closing.offset(by: baseOffset)],
            marked: TextRange(opening.upperBound + baseOffset, closing.lowerBound + baseOffset)
        )
    }

    private static func strikethrough(
        in characters: [Character],
        caretOffset: Int,
        baseOffset: Int
    ) -> EditorInputRuleEffect? {
        let closing = delimiterRunEnding(at: caretOffset, in: characters, delimiter: "~")
        guard closing.length == 2, !isEscaped(closing.lowerBound, in: characters)
        else { return nil }
        guard let opening = nearestOpeningRun(
            before: closing.lowerBound,
            in: characters,
            delimiter: "~",
            length: 2,
            scanLimit: inlineScanLimit
        ) else { return nil }
        guard isValidDelimiterPair(opening: opening, closing: closing, delimiter: "~", in: characters)
        else { return nil }
        return .applyInline(
            marks: [.strikethrough],
            removing: [opening.offset(by: baseOffset), closing.offset(by: baseOffset)],
            marked: TextRange(opening.upperBound + baseOffset, closing.lowerBound + baseOffset)
        )
    }

    private static func link(
        in characters: [Character], caretOffset: Int, baseOffset: Int
    ) -> EditorInputRuleEffect? {
        let closing = caretOffset - 1
        guard !isEscaped(closing, in: characters) else { return nil }
        let lowerBound = max(0, caretOffset - inlineScanLimit)
        guard let separator = lastLinkDestinationOpener(
            before: closing, lowerBound: lowerBound, in: characters
        ),
            let opener = lastUnescaped("[", before: separator - 1, lowerBound: lowerBound, in: characters),
            !isEscaped(opener, in: characters)
        else { return nil }

        let label = TextRange(opener + 1, separator - 1)
        let destination = TextRange(separator + 1, closing)
        guard !label.isEmpty,
            !characters[label.lowerBound].isWhitespace,
            !characters[label.upperBound - 1].isWhitespace,
            isBalancedLinkDestination(destination, in: characters)
        else { return nil }

        return .applyInline(
            marks: [.link(destination: unescapedLinkDestination(destination, in: characters))],
            removing: [
                TextRange(opener + baseOffset, opener + baseOffset + 1),
                TextRange(separator - 1 + baseOffset, closing + 1 + baseOffset),
            ],
            marked: TextRange(label.lowerBound + baseOffset, label.upperBound + baseOffset)
        )
    }

    private static func inlineMarks(forDelimiterRunLength length: Int) -> [BlockContent.InlineMark.Kind] {
        switch length {
        case 1: [.emphasis]
        case 2: [.strong]
        case 3: [.strong, .emphasis]
        default: []
        }
    }

    private static func delimiterRunEnding(
        at caretOffset: Int,
        in characters: [Character],
        delimiter: Character
    ) -> TextRange {
        var lower = caretOffset
        while lower > 0, characters[lower - 1] == delimiter { lower -= 1 }
        return TextRange(lower, caretOffset)
    }

    private static func nearestOpeningRun(
        before upperBound: Int,
        in characters: [Character],
        delimiter: Character,
        length: Int,
        scanLimit: Int
    ) -> TextRange? {
        let lowerBound = max(0, upperBound - scanLimit)
        var index = upperBound - 1
        while index >= lowerBound {
            guard characters[index] == delimiter else {
                index -= 1
                continue
            }
            var runLower = index
            while runLower > lowerBound, characters[runLower - 1] == delimiter { runLower -= 1 }
            var runUpper = index + 1
            while runUpper < upperBound, characters[runUpper] == delimiter { runUpper += 1 }
            let run = TextRange(runLower, runUpper)
            if run.length == length, !isEscaped(run.lowerBound, in: characters) {
                return run
            }
            index = runLower - 1
        }
        return nil
    }

    private static func isValidDelimiterPair(
        opening: TextRange,
        closing: TextRange,
        delimiter: Character,
        in characters: [Character]
    ) -> Bool {
        guard opening.upperBound < closing.lowerBound,
            !characters[opening.upperBound].isWhitespace,
            !characters[closing.lowerBound - 1].isWhitespace
        else { return false }

        let beforeOpening = opening.lowerBound > 0 ? characters[opening.lowerBound - 1] : nil
        let afterOpening = characters[opening.upperBound]
        let beforeClosing = characters[closing.lowerBound - 1]
        let afterClosing = closing.upperBound < characters.count ? characters[closing.upperBound] : nil
        guard leftFlanking(before: beforeOpening, after: afterOpening),
            rightFlanking(before: beforeClosing, after: afterClosing)
        else { return false }

        // CommonMark disallows an underscore delimiter pair in the middle of a word.
        if delimiter == "_", isWord(beforeOpening), isWord(afterOpening) { return false }
        if delimiter == "_", isWord(beforeClosing), isWord(afterClosing) { return false }
        return true
    }

    private static func leftFlanking(before: Character?, after: Character) -> Bool {
        guard !after.isWhitespace else { return false }
        guard !isPunctuation(after) else { return before == nil || before!.isWhitespace || isPunctuation(before!) }
        return true
    }

    private static func rightFlanking(before: Character, after: Character?) -> Bool {
        guard !before.isWhitespace else { return false }
        guard !isPunctuation(before) else { return after == nil || after!.isWhitespace || isPunctuation(after!) }
        return true
    }

    private static func isWord(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.unicodeScalars.allSatisfy { scalar in
            scalar.properties.isAlphabetic || scalar.properties.numericType != nil
        }
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                .initialPunctuation, .finalPunctuation, .otherPunctuation:
                true
            default:
                false
            }
        }
    }

    private static func isEscaped(_ index: Int, in characters: [Character]) -> Bool {
        guard index > 0 else { return false }
        var slashCount = 0
        var cursor = index
        while cursor > 0, characters[cursor - 1] == "\\" {
            slashCount += 1
            cursor -= 1
        }
        return slashCount.isMultiple(of: 2) == false
    }

    /// Returns the exact unmatched opening run. Different-length runs are literal code-span
    /// content and must not flip an odd/even state.
    private static func unmatchedInlineCodeOpener(
        in characters: [Character],
        before caretOffset: Int
    ) -> Int? {
        var openingLength: Int?
        var index = 0
        while index < caretOffset {
            guard characters[index] == "`", !isEscaped(index, in: characters) else {
                index += 1
                continue
            }
            let lowerBound = index
            repeat { index += 1 } while index < caretOffset && characters[index] == "`"
            let runLength = index - lowerBound
            if openingLength == nil {
                openingLength = runLength
            } else if openingLength == runLength {
                openingLength = nil
            }
        }
        return openingLength
    }

    private static func lastUnescaped(
        _ character: Character,
        before upperBound: Int,
        lowerBound: Int,
        in characters: [Character]
    ) -> Int? {
        guard lowerBound < upperBound else { return nil }
        for index in stride(from: upperBound - 1, through: lowerBound, by: -1) {
            if characters[index] == character, !isEscaped(index, in: characters) { return index }
        }
        return nil
    }

    /// The opener we want is the `(` immediately after `]`, not the nearest `(`. A link
    /// destination may itself contain balanced parentheses, e.g. `[x](a(b))`.
    private static func lastLinkDestinationOpener(
        before upperBound: Int,
        lowerBound: Int,
        in characters: [Character]
    ) -> Int? {
        guard lowerBound < upperBound else { return nil }
        for index in stride(from: upperBound - 1, through: lowerBound, by: -1) {
            guard characters[index] == "(", index > lowerBound,
                characters[index - 1] == "]",
                !isEscaped(index, in: characters), !isEscaped(index - 1, in: characters)
            else { continue }
            return index
        }
        return nil
    }

    private static func isBalancedLinkDestination(_ range: TextRange, in characters: [Character]) -> Bool {
        var depth = 0
        for index in range.lowerBound..<range.upperBound {
            let character = characters[index]
            guard !character.isWhitespace else { return false }
            guard !isEscaped(index, in: characters) else { continue }
            switch character {
            case "(":
                depth += 1
            case ")":
                guard depth > 0 else { return false }
                depth -= 1
            default:
                break
            }
        }
        return depth == 0
    }

    /// `swift-markdown` exposes the semantic destination, not its source escaping. Typed
    /// rules therefore remove only Markdown's ASCII punctuation escapes before producing
    /// the same canonical link mark as the whole-document decoder.
    private static func unescapedLinkDestination(
        _ range: TextRange,
        in characters: [Character]
    ) -> String {
        var result = ""
        var index = range.lowerBound
        while index < range.upperBound {
            let character = characters[index]
            if character == "\\", index + 1 < range.upperBound,
                isMarkdownEscapablePunctuation(characters[index + 1]) {
                index += 1
            }
            result.append(characters[index])
            index += 1
        }
        return result
    }

    private static func isMarkdownEscapablePunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 33...47, 58...64, 91...96, 123...126:
                true
            default:
                false
            }
        }
    }
}
