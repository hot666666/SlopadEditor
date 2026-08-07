import SlopadCoreModel

// MARK: - EditorModel MarkdownPrefixShortcuts

extension EditorModel {
    func normalizeShortcutsIfNeeded(
        blockID: BlockID,
        caretOffset: Int,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) {
        guard let block = state.document.block(blockID), block.kind.supportsMarkdownShortcuts else {
            return
        }
        if applyBlockShortcut(blockID: blockID, caretOffset: caretOffset, operations: &operations) {
            changed.insert(blockID)
        }
    }

    private func applyBlockShortcut(
        blockID: BlockID,
        caretOffset: Int,
        operations: inout [EditorOperation]
    ) -> Bool {
        guard let block = state.document.block(blockID), block.kind.supportsMarkdownShortcuts else {
            return false
        }
        guard let match = markdownPrefixShortcutMatch(
            in: block.content.text,
            caretOffset: caretOffset
        ) else { return false }

        guard
            case .success = state.document.updateContent(
                blockID: blockID,
                { content in
                    content.delete(TextRange(0, match.marker.count))
                })
        else {
            return false
        }
        guard case .success = state.document.setBlockKind(blockID: blockID, kind: match.kind) else {
            return false
        }
        state.selection = .caret(blockID: blockID, offset: 0)
        operations.append(.refreshMarker)
        return true
    }
}

// MARK: - Markdown Prefix Matching

private func markdownPrefixShortcutMatch(
    in text: String,
    caretOffset: Int
) -> (marker: String, kind: BlockKind)? {
    guard
        caretOffset >= 0,
        caretOffset <= markdownPrefixShortcutMaximumCandidateLength(),
        let caretIndex = text.index(
            text.startIndex,
            offsetBy: caretOffset,
            limitedBy: text.endIndex
        )
    else { return nil }

    let marker = String(text[..<caretIndex])
    return markdownPrefixShortcutMatch(marker: marker)
}

private func markdownPrefixShortcutMatch(
    marker: String
) -> (marker: String, kind: BlockKind)? {
    if let fixed = markdownPrefixShortcutFixedRules.first(where: { $0.marker == marker }) {
        return fixed
    }

    return markdownOrderedPrefixShortcutMatch(marker: marker)
}

private func markdownOrderedPrefixShortcutMatch(
    marker: String
) -> (marker: String, kind: BlockKind)? {
    guard marker.hasSuffix(markdownOrderedPrefixShortcutSuffix) else {
        return nil
    }

    let numberText = marker.dropLast(markdownOrderedPrefixShortcutSuffix.count)
    guard
        !numberText.isEmpty,
        numberText.count <= markdownOrderedPrefixShortcutMaximumDigitCount,
        numberText.allSatisfy(\.isNumber),
        let number = Int(numberText)
    else {
        return nil
    }

    return (
        marker: marker,
        kind: .orderedListItem(restartNumber: number == 1 ? nil : number)
    )
}

private func markdownPrefixShortcutMaximumCandidateLength() -> Int {
    let fixedMaximum = markdownPrefixShortcutFixedRules.map { $0.marker.count }.max() ?? 0
    let orderedMaximum =
        markdownOrderedPrefixShortcutMaximumDigitCount + markdownOrderedPrefixShortcutSuffix.count
    return max(fixedMaximum, orderedMaximum)
}

private let markdownPrefixShortcutFixedRules: [(marker: String, kind: BlockKind)] = [
    (marker: "# ", kind: .heading(level: .h1)),
    (marker: "## ", kind: .heading(level: .h2)),
    (marker: "### ", kind: .heading(level: .h3)),
    (marker: "- ", kind: .unorderedListItem),
    (marker: "* ", kind: .unorderedListItem),
    (marker: "> ", kind: .quote),
    (marker: "[x] ", kind: .todo(isChecked: true)),
    (marker: "[X] ", kind: .todo(isChecked: true)),
    (marker: "[ ] ", kind: .todo(isChecked: false)),
    (marker: "[] ", kind: .todo(isChecked: false)),
    (marker: "```", kind: .codeBlock(language: nil)),
]

private let markdownOrderedPrefixShortcutSuffix = ". "
private let markdownOrderedPrefixShortcutMaximumDigitCount = 9

// MARK: - Shortcut Eligibility

extension BlockKind {
    fileprivate var supportsMarkdownShortcuts: Bool {
        if case .codeBlock = self {
            return false
        }
        return true
    }
}
