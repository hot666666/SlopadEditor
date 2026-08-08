import SlopadCoreModel

/// Deterministic, fail-closed conversion from the core block tree to Markdown.
///
/// This type deliberately consumes `EditorBlockInput` rather than `Document`: the latter is
/// package implementation state, while inputs are the public canonical snapshot vocabulary.
struct MarkdownEncoder {
    struct Result {
        var markdown: String
        var diagnostics: [MarkdownEncodingDiagnostic]
    }

    private enum ListFamily: Equatable {
        case unordered
        case ordered
    }

    private struct CodeSpan {
        var delimiter: String
        var content: String
    }

    private static let maximumSupportedDepth = 64
    private static let escapablePunctuation = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

    private let inputs: [EditorBlockInput]
    private var records: [BlockID: EditorBlockInput] = [:]
    private var rootIDs: [BlockID] = []
    private var childIDsByParent: [BlockID: [BlockID]] = [:]
    private var diagnostics: [MarkdownEncodingDiagnostic] = []

    init(blocks: [EditorBlockInput]) {
        self.inputs = blocks
    }

    mutating func encode() -> Result {
        validateTree()
        guard diagnostics.isEmpty else {
            sortDiagnosticsByCanonicalOccurrence()
            return Result(markdown: "", diagnostics: diagnostics)
        }

        validateRepresentability()
        guard diagnostics.isEmpty else {
            sortDiagnosticsByCanonicalOccurrence()
            return Result(markdown: "", diagnostics: diagnostics)
        }

        return Result(markdown: renderSiblings(rootIDs), diagnostics: [])
    }

    // MARK: - Canonical tree validation

    private mutating func validateTree() {
        guard !inputs.isEmpty else {
            appendDiagnostic(.emptyDocument, blockID: nil)
            return
        }

        for input in inputs {
            if records.updateValue(input, forKey: input.id) != nil {
                appendDiagnostic(.duplicateBlockID, blockID: input.id)
            }
        }
        guard diagnostics.isEmpty else { return }

        for input in inputs {
            if let parentID = input.parentID {
                guard records[parentID] != nil else {
                    appendDiagnostic(.missingParent, blockID: input.id)
                    continue
                }
                childIDsByParent[parentID, default: []].append(input.id)
            } else {
                rootIDs.append(input.id)
            }
        }
        guard diagnostics.isEmpty else { return }

        var reportedCycles: Set<BlockID> = []
        for input in inputs {
            var pathIndexes: [BlockID: Int] = [:]
            var path: [BlockID] = []
            var currentID: BlockID? = input.id
            while let blockID = currentID {
                if let firstIndex = pathIndexes[blockID] {
                    let cycleIDs = path[firstIndex...]
                    let representative = cycleIDs.min { lhs, rhs in
                        inputIndex(for: lhs) < inputIndex(for: rhs)
                    }!
                    if reportedCycles.insert(representative).inserted {
                        appendDiagnostic(.cycle, blockID: representative)
                    }
                    break
                }
                pathIndexes[blockID] = path.count
                path.append(blockID)
                currentID = records[blockID]?.parentID
            }
        }
        guard diagnostics.isEmpty else { return }

        var depthFirstOrder: [BlockID] = []
        var stack = Array(rootIDs.reversed())
        while let blockID = stack.popLast() {
            depthFirstOrder.append(blockID)
            stack.append(contentsOf: (childIDsByParent[blockID] ?? []).reversed())
        }
        guard depthFirstOrder == inputs.map(\.id) else {
            appendDiagnostic(.noncanonicalDepthFirstOrder, blockID: nil)
            return
        }

        let isExactEmptyDocument = inputs.count == 1
            && inputs[0].parentID == nil
            && inputs[0].kind == .paragraph
            && inputs[0].content.text.isEmpty
            && inputs[0].content.marks.isEmpty
        for input in inputs where input.kind == .paragraph && input.content.text.isEmpty {
            guard isExactEmptyDocument else {
                appendDiagnostic(.unrepresentableEmptyParagraph, blockID: input.id)
                continue
            }
        }

        for input in inputs where !(childIDsByParent[input.id] ?? []).isEmpty {
            guard canContainChildren(input.kind) else {
                appendDiagnostic(.unsupportedChildHierarchy, blockID: input.id)
                continue
            }
            if input.content.text.isEmpty,
               let firstChildID = childIDsByParent[input.id]?.first,
               records[firstChildID]?.kind == .paragraph {
                appendDiagnostic(.ambiguousEmptyContainer, blockID: input.id)
            }
        }

        var depthStack = rootIDs.reversed().map { (id: $0, containerDepth: 0) }
        while let current = depthStack.popLast(), let input = records[current.id] {
            let depth = current.containerDepth + (isContainer(input.kind) ? 1 : 0)
            if depth > Self.maximumSupportedDepth {
                appendDiagnostic(
                    .excessiveNesting(maximumDepth: Self.maximumSupportedDepth),
                    blockID: current.id
                )
                continue
            }
            for childID in (childIDsByParent[current.id] ?? []).reversed() {
                depthStack.append((id: childID, containerDepth: depth))
            }
        }

        validateOrderedListRestarts()
    }

    private mutating func validateOrderedListRestarts() {
        let siblingGroups = [rootIDs] + childIDsByParent.values
        for siblings in siblingGroups {
            for index in siblings.indices {
                guard case .orderedListItem(let restartNumber) = records[siblings[index]]?.kind,
                      let restartNumber else { continue }
                let continuesOrderedList = index > siblings.startIndex
                    && listFamily(for: records[siblings[index - 1]]?.kind) == .ordered
                if continuesOrderedList || restartNumber <= 1 {
                    appendDiagnostic(.invalidOrderedListRestart, blockID: siblings[index])
                }
            }
        }
    }

    // MARK: - Markdown representability validation

    private mutating func validateRepresentability() {
        for input in inputs {
            let content = input.content
            guard content.text.utf8.allSatisfy({ $0 != 0 }), !content.text.contains("\r") else {
                appendDiagnostic(.unrepresentableText, blockID: input.id)
                continue
            }

            guard canonicalizedMarks(content.marks, textLength: content.text.count) == content.marks else {
                appendDiagnostic(.noncanonicalInlineMarks, blockID: input.id)
                continue
            }

            validateInlineMarks(content.marks, in: content.text, blockID: input.id)

            switch input.kind {
            case .divider:
                if !content.text.isEmpty || !content.marks.isEmpty {
                    appendDiagnostic(.nonemptyDivider, blockID: input.id)
                }

            case .codeBlock(let language):
                if !content.marks.isEmpty {
                    appendDiagnostic(.inlineMarksInCodeBlock, blockID: input.id)
                }
                if !content.text.isEmpty && !content.text.hasSuffix("\n") {
                    appendDiagnostic(.codeBlockRequiresTrailingLineBreak, blockID: input.id)
                }
                if let language,
                   language.isEmpty || language.contains(where: \.isWhitespace) || language.contains("`") {
                    appendDiagnostic(.invalidCodeBlockLanguage, blockID: input.id)
                }

            default:
                break
            }
        }
    }

    private mutating func validateInlineMarks(
        _ marks: [BlockContent.InlineMark],
        in text: String,
        blockID: BlockID
    ) {
        for index in marks.indices {
            for otherIndex in marks.indices where otherIndex > index {
                let first = marks[index].range
                let second = marks[otherIndex].range
                guard first.intersects(second),
                      !first.contains(second),
                      !second.contains(first) else { continue }
                appendDiagnostic(.crossingInlineMarks, blockID: blockID)
                break
            }
        }

        let links = marks.filter {
            if case .link = $0.kind { return true }
            return false
        }
        for index in links.indices {
            if case .link(let destination) = links[index].kind,
               destination.utf8.contains(0) || destination.contains(where: { $0 == "\r" || $0 == "\n" }) {
                appendDiagnostic(.invalidLinkDestination, blockID: blockID)
                break
            }
            for otherIndex in links.indices where otherIndex > index {
                if links[index].range.intersects(links[otherIndex].range) {
                    appendDiagnostic(.intersectingLinks, blockID: blockID)
                    break
                }
            }
        }

        for codeMark in marks where codeMark.kind == .code {
            let codeText = substring(text, in: codeMark.range)
            if codeText.contains("\n") || codeText.contains("\r") {
                appendDiagnostic(.inlineCodeContainsLineBreak, blockID: blockID)
            }
            for otherMark in marks where otherMark != codeMark && codeMark.range.intersects(otherMark.range) {
                guard otherMark.range.contains(codeMark.range) else {
                    appendDiagnostic(.unsupportedInlineCodeNesting, blockID: blockID)
                    break
                }
            }
        }
    }

    // MARK: - Block rendering

    private func renderSiblings(_ siblingIDs: [BlockID]) -> String {
        var result = ""
        var previousFamily: ListFamily?

        for id in siblingIDs {
            guard let input = records[id] else { continue }
            let family = listFamily(for: input.kind)
            if !result.isEmpty {
                result += family != nil && family == previousFamily ? "\n" : "\n\n"
            }
            result += renderBlock(input)
            previousFamily = family
        }
        return result
    }

    private func renderBlock(_ input: EditorBlockInput) -> String {
        switch input.kind {
        case .paragraph:
            return renderInline(input.content)

        case .heading(let level):
            return String(repeating: "#", count: level.rawValue) + " " + renderInline(input.content)

        case .quote:
            return renderQuote(input)

        case .unorderedListItem, .orderedListItem, .todo:
            return renderListItem(input)

        case .codeBlock(let language):
            return renderCodeBlock(content: input.content.text, language: language)

        case .divider:
            return "---"
        }
    }

    private func renderQuote(_ input: EditorBlockInput) -> String {
        let children = childIDsByParent[input.id] ?? []
        var body = renderInline(input.content)
        if !children.isEmpty {
            let renderedChildren = renderSiblings(children)
            body = body.isEmpty ? renderedChildren : body + "\n\n" + renderedChildren
        }
        guard !body.isEmpty else { return ">" }
        return body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.isEmpty ? ">" : "> " + line }
            .joined(separator: "\n")
    }

    private func renderListItem(_ input: EditorBlockInput) -> String {
        let marker: String
        switch input.kind {
        case .unorderedListItem:
            marker = "- "
        case .todo(let isChecked):
            marker = isChecked ? "- [x] " : "- [ ] "
        case .orderedListItem(let restartNumber):
            marker = "\(restartNumber ?? 1). "
        default:
            preconditionFailure("Only list kinds reach renderListItem")
        }

        let ownLines = renderInline(input.content)
            .split(separator: "\n", omittingEmptySubsequences: false)
        var result = marker + (ownLines.first.map(String.init) ?? "")
        let continuationPrefix = String(repeating: " ", count: marker.count)
        for line in ownLines.dropFirst() {
            result += "\n" + continuationPrefix + line
        }

        let children = childIDsByParent[input.id] ?? []
        if !children.isEmpty {
            result += "\n\n" + indent(renderSiblings(children), by: continuationPrefix)
        }
        return result
    }

    private func renderCodeBlock(content: String, language: String?) -> String {
        let longestRun = longestBacktickRun(in: content)
        let fence = String(repeating: "`", count: max(3, longestRun + 1))
        let info = language.map { " \($0)" } ?? ""
        return fence + info + "\n" + content + fence
    }

    // MARK: - Inline rendering

    private func renderInline(_ content: BlockContent) -> String {
        guard !content.text.isEmpty else { return "" }

        let emphasisDelimiters = emphasisDelimiters(for: content.marks)
        let delimiterEntityOffsets = delimiterEntityOffsets(
            in: content.text,
            marks: content.marks
        )

        var boundaries: Set<Int> = [0, content.text.count]
        for mark in content.marks {
            boundaries.insert(mark.range.lowerBound)
            boundaries.insert(mark.range.upperBound)
        }
        let orderedBoundaries = boundaries.sorted()

        var result = ""
        var openMarks: [BlockContent.InlineMark] = []
        for (lowerBound, upperBound) in zip(orderedBoundaries, orderedBoundaries.dropFirst()) {
            let range = TextRange(lowerBound, upperBound)
            let activeMarks = content.marks
                .filter { $0.range.contains(range) }
                .sorted { inlineNestingOrder($0.kind, $1.kind) }
            let desiredMarks = activeMarks.filter { $0.kind != .code }
            let commonPrefixLength = zip(openMarks, desiredMarks)
                .prefix { $0.kind == $1.kind }
                .count

            for mark in openMarks.dropFirst(commonPrefixLength).reversed() {
                result += closingDelimiter(mark, emphasisDelimiters: emphasisDelimiters)
            }
            openMarks.removeLast(openMarks.count - commonPrefixLength)
            for mark in desiredMarks.dropFirst(commonPrefixLength) {
                result += openingDelimiter(mark, emphasisDelimiters: emphasisDelimiters)
                openMarks.append(mark)
            }

            let text = substring(content.text, in: range)
            if activeMarks.contains(where: { $0.kind == .code }) {
                let codeSpan = makeCodeSpan(text)
                result += codeSpan.delimiter + codeSpan.content + codeSpan.delimiter
            } else {
                result += escapeText(
                    text,
                    startingAt: lowerBound,
                    entityOffsets: delimiterEntityOffsets
                )
            }
        }
        for mark in openMarks.reversed() {
            result += closingDelimiter(mark, emphasisDelimiters: emphasisDelimiters)
        }
        return result
    }

    private func inlineNestingOrder(
        _ lhs: BlockContent.InlineMark.Kind,
        _ rhs: BlockContent.InlineMark.Kind
    ) -> Bool {
        let rank: (BlockContent.InlineMark.Kind) -> Int = { kind in
            switch kind {
            case .strong: 0
            case .emphasis: 1
            case .strikethrough: 2
            case .link: 3
            case .code: 4
            }
        }
        if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
        return lhs < rhs
    }

    private func openingDelimiter(
        _ mark: BlockContent.InlineMark,
        emphasisDelimiters: [BlockContent.InlineMark: String]
    ) -> String {
        switch mark.kind {
        case .strong: "**"
        case .emphasis: emphasisDelimiters[mark, default: "_"]
        case .strikethrough: "~~"
        case .link: "["
        case .code: ""
        }
    }

    private func closingDelimiter(
        _ mark: BlockContent.InlineMark,
        emphasisDelimiters: [BlockContent.InlineMark: String]
    ) -> String {
        switch mark.kind {
        case .strong: "**"
        case .emphasis: emphasisDelimiters[mark, default: "_"]
        case .strikethrough: "~~"
        case .link(let destination): "](\(encodeLinkDestination(destination)))"
        case .code: ""
        }
    }

    private func makeCodeSpan(_ text: String) -> CodeSpan {
        let delimiter = String(repeating: "`", count: longestBacktickRun(in: text) + 1)
        let needsPadding = !text.allSatisfy(\.isWhitespace)
            && (text.first?.isWhitespace == true || text.last?.isWhitespace == true)
        return CodeSpan(
            delimiter: delimiter,
            content: needsPadding ? " \(text) " : text
        )
    }

    private func encodeLinkDestination(_ destination: String) -> String {
        "<\(escapePunctuation(destination))>"
    }

    private func escapeText(
        _ text: String,
        startingAt offset: Int,
        entityOffsets: Set<Int>
    ) -> String {
        var result = ""
        for (index, character) in text.enumerated() {
            if entityOffsets.contains(offset + index) {
                result += character.unicodeScalars
                    .map { "&#x" + String($0.value, radix: 16) + ";" }
                    .joined()
            } else if character == "\n" {
                result.append("\\")
                result.append("\n")
            } else if Self.escapablePunctuation.contains(character) {
                result += "\\" + String(character)
            } else {
                result.append(character)
            }
        }
        return result
    }

    private func delimiterEntityOffsets(
        in text: String,
        marks: [BlockContent.InlineMark]
    ) -> Set<Int> {
        var offsets: Set<Int> = []
        for mark in marks where mark.kind != .code {
            if mark.range.lowerBound > 0,
               !character(at: mark.range.lowerBound - 1, in: text).isWhitespace {
                offsets.insert(mark.range.lowerBound - 1)
            }
            if mark.range.upperBound < text.count,
               !character(at: mark.range.upperBound, in: text).isWhitespace {
                offsets.insert(mark.range.upperBound)
            }
        }
        return offsets
    }

    private func emphasisDelimiters(
        for marks: [BlockContent.InlineMark]
    ) -> [BlockContent.InlineMark: String] {
        Dictionary(
            uniqueKeysWithValues: marks.compactMap { emphasisMark in
                guard emphasisMark.kind == .emphasis else { return nil }
                let hasNestedFormatting = marks.contains { otherMark in
                    otherMark != emphasisMark && otherMark.range.intersects(emphasisMark.range)
                }
                return (emphasisMark, hasNestedFormatting ? "*" : "_")
            }
        )
    }

    private func escapePunctuation(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            if Self.escapablePunctuation.contains(character) {
                result += "\\" + String(character)
            } else {
                result.append(character)
            }
        }
    }

    // MARK: - Local helpers

    private mutating func appendDiagnostic(
        _ kind: MarkdownEncodingDiagnostic.Kind,
        blockID: BlockID?
    ) {
        let diagnostic = MarkdownEncodingDiagnostic(kind: kind, blockID: blockID)
        guard !diagnostics.contains(diagnostic) else { return }
        diagnostics.append(diagnostic)
    }

    private func inputIndex(for id: BlockID) -> Int {
        inputs.firstIndex(where: { $0.id == id }) ?? .max
    }

    private mutating func sortDiagnosticsByCanonicalOccurrence() {
        diagnostics = diagnostics.enumerated().sorted { lhs, rhs in
            let lhsIndex = lhs.element.blockID.map(inputIndex(for:)) ?? -1
            let rhsIndex = rhs.element.blockID.map(inputIndex(for:)) ?? -1
            return lhsIndex == rhsIndex ? lhs.offset < rhs.offset : lhsIndex < rhsIndex
        }.map(\.element)
    }

    private func canContainChildren(_ kind: BlockKind) -> Bool {
        isContainer(kind)
    }

    private func isContainer(_ kind: BlockKind) -> Bool {
        switch kind {
        case .quote, .unorderedListItem, .orderedListItem, .todo:
            true
        default:
            false
        }
    }

    private func listFamily(for kind: BlockKind?) -> ListFamily? {
        guard let kind else { return nil }
        switch kind {
        case .unorderedListItem, .todo:
            return .unordered
        case .orderedListItem:
            return .ordered
        default:
            return nil
        }
    }

    private func indent(_ markdown: String, by prefix: String) -> String {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private func substring(_ text: String, in range: TextRange) -> String {
        let lowerBound = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upperBound = text.index(text.startIndex, offsetBy: range.upperBound)
        return String(text[lowerBound..<upperBound])
    }

    private func character(at offset: Int, in text: String) -> Character {
        text[text.index(text.startIndex, offsetBy: offset)]
    }


    private func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    private func canonicalizedMarks(
        _ marks: [BlockContent.InlineMark],
        textLength: Int
    ) -> [BlockContent.InlineMark] {
        let clamped = marks.compactMap { mark -> BlockContent.InlineMark? in
            guard mark.range.lowerBound >= 0,
                  mark.range.upperBound >= mark.range.lowerBound,
                  mark.range.upperBound <= textLength,
                  !mark.range.isEmpty else { return nil }
            return mark
        }

        let grouped = Dictionary(grouping: clamped, by: \.kind)
        var normalized: [BlockContent.InlineMark] = []
        for (kind, group) in grouped {
            let sorted = group.sorted {
                if $0.range.lowerBound == $1.range.lowerBound {
                    return $0.range.upperBound < $1.range.upperBound
                }
                return $0.range.lowerBound < $1.range.lowerBound
            }
            var current: TextRange?
            for mark in sorted {
                guard var range = current else {
                    current = mark.range
                    continue
                }
                if range.intersects(mark.range) || range.isAdjacent(to: mark.range) {
                    range.upperBound = max(range.upperBound, mark.range.upperBound)
                    current = range
                } else {
                    normalized.append(BlockContent.InlineMark(kind: kind, range: range))
                    current = mark.range
                }
            }
            if let current {
                normalized.append(BlockContent.InlineMark(kind: kind, range: current))
            }
        }

        return normalized.sorted {
            if $0.range.lowerBound != $1.range.lowerBound {
                return $0.range.lowerBound < $1.range.lowerBound
            }
            if $0.range.upperBound != $1.range.upperBound {
                return $0.range.upperBound < $1.range.upperBound
            }
            return $0.kind < $1.kind
        }
    }
}
