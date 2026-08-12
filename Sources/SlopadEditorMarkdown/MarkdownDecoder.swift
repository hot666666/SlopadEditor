internal import Markdown
import SlopadEditorCoreModel

struct MarkdownDecoder {
    struct Result {
        var blocks: [EditorBlockInput]
        var diagnostics: [MarkdownDiagnostic]
    }

    private enum ListItemKind {
        case unordered
        case ordered(restartNumber: Int?)
    }

    private enum BlockTask {
        case markup(any Markup, parentID: BlockID?)
        case listItem(ListItem, parentID: BlockID?, kind: ListItemKind)
    }

    private enum InlineTask {
        case enter(any Markup)
        case closeMark(BlockContent.InlineMark.Kind, lowerBound: Int)
    }

    private struct InlineMarkCandidate {
        var kind: BlockContent.InlineMark.Kind
        var lowerUTF8Bound: Int
        var upperUTF8Bound: Int
    }

    private struct GraphemeBoundary {
        var utf8Offset: Int
        var graphemeOffset: Int
    }

    private let markdown: String
    private let wholeInputRange: MarkdownSourceRange
    private var blocks: [EditorBlockInput] = []
    private var diagnostics: [MarkdownDiagnostic] = []

    init(markdown: String) {
        self.markdown = markdown
        self.wholeInputRange = Self.sourceRangeCoveringWholeInput(markdown)
    }

    mutating func decode() -> Result {
        guard !markdown.allSatisfy({ $0.isWhitespace }) else {
            return Result(blocks: [EditorBlockInput()], diagnostics: [])
        }
        guard !MarkdownNestingPreflight.exceedsSupportedDepth(in: markdown) else {
            return Result(
                blocks: [],
                diagnostics: [
                    MarkdownDiagnostic(
                        kind: .excessiveNesting(
                            maximumDepth: MarkdownNestingPreflight.maximumSupportedDepth
                        ),
                        sourceRange: wholeInputRange
                    )
                ]
            )
        }

        let document = Document(parsing: markdown, options: [.disableSmartOpts])
        var tasks: [BlockTask] = []
        pushMarkupChildren(of: document, parentID: nil, onto: &tasks)

        while let task = tasks.popLast() {
            switch task {
            case .markup(let markup, let parentID):
                processBlock(markup, parentID: parentID, tasks: &tasks)
            case .listItem(let item, let parentID, let kind):
                processListItem(item, parentID: parentID, kind: kind, tasks: &tasks)
            }
        }

        if blocks.isEmpty, diagnostics.isEmpty {
            blocks = [EditorBlockInput()]
        }

        diagnostics.sort {
            if $0.sourceRange.lowerBound != $1.sourceRange.lowerBound {
                return $0.sourceRange.lowerBound < $1.sourceRange.lowerBound
            }
            return $0.sourceRange.upperBound < $1.sourceRange.upperBound
        }
        return Result(blocks: blocks, diagnostics: diagnostics)
    }

    private mutating func processBlock(
        _ markup: any Markup,
        parentID: BlockID?,
        tasks: inout [BlockTask]
    ) {
        switch markup {
        case let paragraph as Paragraph:
            appendTextBlock(kind: .paragraph, inlineContainer: paragraph, parentID: parentID)

        case let heading as Heading:
            guard let level = BlockKind.HeadingLevel(rawValue: heading.level) else {
                appendDiagnostic(.heading(level: heading.level), for: heading)
                return
            }
            appendTextBlock(
                kind: .heading(level: level),
                inlineContainer: heading,
                parentID: parentID
            )

        case let quote as BlockQuote:
            let id = BlockID()
            let first = quote.child(at: 0)
            let content: BlockContent
            let childStart: Int
            if let paragraph = first as? Paragraph {
                content = decodeInlineContent(of: paragraph)
                childStart = 1
            } else {
                content = BlockContent()
                childStart = 0
            }
            blocks.append(
                EditorBlockInput(id: id, parentID: parentID, kind: .quote, content: content)
            )
            pushMarkupChildren(of: quote, startingAt: childStart, parentID: id, onto: &tasks)

        case let unorderedList as UnorderedList:
            pushListItems(
                of: unorderedList,
                parentID: parentID,
                orderedStart: nil,
                onto: &tasks
            )

        case let orderedList as OrderedList:
            pushListItems(
                of: orderedList,
                parentID: parentID,
                orderedStart: orderedList.startIndex,
                onto: &tasks
            )

        case let codeBlock as CodeBlock:
            blocks.append(
                EditorBlockInput(
                    parentID: parentID,
                    kind: .codeBlock(language: codeBlock.language),
                    content: BlockContent(text: codeBlock.code)
                )
            )

        case is ThematicBreak:
            blocks.append(EditorBlockInput(parentID: parentID, kind: .divider))

        case is Table:
            appendDiagnostic(.table, for: markup)
        case is HTMLBlock:
            appendDiagnostic(.html, for: markup)
        case is BlockDirective:
            appendDiagnostic(.blockDirective, for: markup)
        case is CustomBlock:
            appendDiagnostic(.customBlock, for: markup)
        case is DoxygenAbstract, is DoxygenDiscussion, is DoxygenNote,
            is DoxygenParameter, is DoxygenReturns:
            appendDiagnostic(.doxygenCommand, for: markup)
        case is ListItem:
            appendDiagnostic(.customBlock, for: markup)
        default:
            appendDiagnostic(.customBlock, for: markup)
        }
    }

    private mutating func processListItem(
        _ item: ListItem,
        parentID: BlockID?,
        kind: ListItemKind,
        tasks: inout [BlockTask]
    ) {
        let blockKind: BlockKind
        switch kind {
        case .unordered:
            switch item.checkbox {
            case .checked?:
                blockKind = .todo(isChecked: true)
            case .unchecked?:
                blockKind = .todo(isChecked: false)
            case nil:
                blockKind = .unorderedListItem
            }
        case .ordered(let restartNumber):
            guard item.checkbox == nil else {
                appendDiagnostic(.orderedTask, for: item)
                return
            }
            blockKind = .orderedListItem(restartNumber: restartNumber)
        }

        let id = BlockID()
        let first = item.child(at: 0)
        let content: BlockContent
        let childStart: Int
        if let paragraph = first as? Paragraph {
            content = decodeInlineContent(of: paragraph)
            childStart = 1
        } else {
            content = BlockContent()
            childStart = 0
        }
        blocks.append(
            EditorBlockInput(id: id, parentID: parentID, kind: blockKind, content: content)
        )
        pushMarkupChildren(of: item, startingAt: childStart, parentID: id, onto: &tasks)
    }

    private mutating func appendTextBlock(
        kind: BlockKind,
        inlineContainer: any Markup,
        parentID: BlockID?
    ) {
        blocks.append(
            EditorBlockInput(
                parentID: parentID,
                kind: kind,
                content: decodeInlineContent(of: inlineContainer)
            )
        )
    }

    private mutating func decodeInlineContent(of container: any Markup) -> BlockContent {
        var text = ""
        var utf8Offset = 0
        var markCandidates: [InlineMarkCandidate] = []
        var tasks: [InlineTask] = []
        pushInlineChildren(of: container, onto: &tasks)

        while let task = tasks.popLast() {
            switch task {
            case .closeMark(let kind, let lowerBound):
                guard lowerBound < utf8Offset else { continue }
                markCandidates.append(
                    InlineMarkCandidate(
                        kind: kind,
                        lowerUTF8Bound: lowerBound,
                        upperUTF8Bound: utf8Offset
                    )
                )

            case .enter(let markup):
                switch markup {
                case let plainText as Text:
                    append(plainText.string, to: &text, utf8Offset: &utf8Offset)

                case let inlineCode as InlineCode:
                    let lowerBound = utf8Offset
                    append(inlineCode.code, to: &text, utf8Offset: &utf8Offset)
                    if lowerBound < utf8Offset {
                        markCandidates.append(
                            InlineMarkCandidate(
                                kind: .code,
                                lowerUTF8Bound: lowerBound,
                                upperUTF8Bound: utf8Offset
                            )
                        )
                    }

                case is SoftBreak:
                    append(" ", to: &text, utf8Offset: &utf8Offset)
                case is LineBreak:
                    append("\n", to: &text, utf8Offset: &utf8Offset)

                case let strong as Strong:
                    openMark(.strong, container: strong, at: utf8Offset, tasks: &tasks)
                case let emphasis as Emphasis:
                    openMark(.emphasis, container: emphasis, at: utf8Offset, tasks: &tasks)
                case let strikethrough as Strikethrough:
                    openMark(
                        .strikethrough,
                        container: strikethrough,
                        at: utf8Offset,
                        tasks: &tasks
                    )

                case let link as Link:
                    guard link.title == nil else {
                        appendDiagnostic(.linkTitle, for: link)
                        continue
                    }
                    guard link.childCount > 0 else {
                        appendDiagnostic(.emptyLink, for: link)
                        continue
                    }
                    openMark(
                        .link(destination: link.destination ?? ""),
                        container: link,
                        at: utf8Offset,
                        tasks: &tasks
                    )

                case is Image:
                    appendDiagnostic(.image, for: markup)
                case is InlineHTML:
                    appendDiagnostic(.html, for: markup)
                case is CustomInline:
                    appendDiagnostic(.customInline, for: markup)
                case is InlineAttributes:
                    appendDiagnostic(.inlineAttributes, for: markup)
                case is SymbolLink:
                    appendDiagnostic(.symbolLink, for: markup)
                default:
                    appendDiagnostic(.customInline, for: markup)
                }
            }
        }

        let boundaries = graphemeBoundaries(in: text)
        let marks = markCandidates.compactMap { candidate in
            outwardNormalizedMark(candidate, boundaries: boundaries)
        }
        return BlockContent(text: text, marks: canonicalizedMarks(marks))
    }

    private func append(
        _ fragment: String,
        to text: inout String,
        utf8Offset: inout Int
    ) {
        text.append(fragment)
        utf8Offset += fragment.utf8.count
    }

    private func graphemeBoundaries(in text: String) -> [GraphemeBoundary] {
        var boundaries = [GraphemeBoundary(utf8Offset: 0, graphemeOffset: 0)]
        var index = text.startIndex
        var utf8Offset = 0
        var graphemeOffset = 0

        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            utf8Offset += text[index..<nextIndex].utf8.count
            graphemeOffset += 1
            boundaries.append(
                GraphemeBoundary(
                    utf8Offset: utf8Offset,
                    graphemeOffset: graphemeOffset
                )
            )
            index = nextIndex
        }
        return boundaries
    }

    private func outwardNormalizedMark(
        _ candidate: InlineMarkCandidate,
        boundaries: [GraphemeBoundary]
    ) -> BlockContent.InlineMark? {
        let lowerBound = boundary(
            atOrBefore: candidate.lowerUTF8Bound,
            in: boundaries
        ).graphemeOffset
        let upperBound = boundary(
            atOrAfter: candidate.upperUTF8Bound,
            in: boundaries
        ).graphemeOffset
        guard lowerBound < upperBound else { return nil }
        return BlockContent.InlineMark(
            kind: candidate.kind,
            range: TextRange(lowerBound, upperBound)
        )
    }

    private func boundary(
        atOrBefore utf8Offset: Int,
        in boundaries: [GraphemeBoundary]
    ) -> GraphemeBoundary {
        var lowerIndex = 0
        var upperIndex = boundaries.count
        while lowerIndex < upperIndex {
            let middleIndex = lowerIndex + (upperIndex - lowerIndex) / 2
            if boundaries[middleIndex].utf8Offset <= utf8Offset {
                lowerIndex = middleIndex + 1
            } else {
                upperIndex = middleIndex
            }
        }
        return boundaries[lowerIndex - 1]
    }

    private func boundary(
        atOrAfter utf8Offset: Int,
        in boundaries: [GraphemeBoundary]
    ) -> GraphemeBoundary {
        var lowerIndex = 0
        var upperIndex = boundaries.count
        while lowerIndex < upperIndex {
            let middleIndex = lowerIndex + (upperIndex - lowerIndex) / 2
            if boundaries[middleIndex].utf8Offset < utf8Offset {
                lowerIndex = middleIndex + 1
            } else {
                upperIndex = middleIndex
            }
        }
        return boundaries[lowerIndex]
    }

    private func openMark(
        _ kind: BlockContent.InlineMark.Kind,
        container: any Markup,
        at lowerBound: Int,
        tasks: inout [InlineTask]
    ) {
        tasks.append(.closeMark(kind, lowerBound: lowerBound))
        pushInlineChildren(of: container, onto: &tasks)
    }

    private func canonicalizedMarks(
        _ marks: [BlockContent.InlineMark]
    ) -> [BlockContent.InlineMark] {
        let grouped = Dictionary(grouping: marks, by: \.kind)
        var result: [BlockContent.InlineMark] = []

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
                    result.append(BlockContent.InlineMark(kind: kind, range: range))
                    current = mark.range
                }
            }
            if let current {
                result.append(BlockContent.InlineMark(kind: kind, range: current))
            }
        }

        return result.sorted {
            if $0.range.lowerBound != $1.range.lowerBound {
                return $0.range.lowerBound < $1.range.lowerBound
            }
            if $0.range.upperBound != $1.range.upperBound {
                return $0.range.upperBound < $1.range.upperBound
            }
            return $0.kind < $1.kind
        }
    }

    private mutating func appendDiagnostic(
        _ kind: MarkdownDiagnostic.Kind,
        for markup: any Markup
    ) {
        diagnostics.append(
            MarkdownDiagnostic(
                kind: kind,
                sourceRange: nearestSourceRange(for: markup)
            )
        )
    }

    private func nearestSourceRange(for markup: any Markup) -> MarkdownSourceRange {
        var candidate: (any Markup)? = markup
        while let current = candidate {
            if let range = current.range {
                return MarkdownSourceRange(
                    lowerBound: MarkdownSourcePosition(
                        line: range.lowerBound.line,
                        utf8Column: range.lowerBound.column
                    ),
                    upperBound: MarkdownSourcePosition(
                        line: range.upperBound.line,
                        utf8Column: range.upperBound.column
                    )
                )
            }
            candidate = current.parent
        }
        return wholeInputRange
    }

    private func pushMarkupChildren(
        of container: any Markup,
        startingAt start: Int = 0,
        parentID: BlockID?,
        onto tasks: inout [BlockTask]
    ) {
        guard start < container.childCount else { return }
        for index in (start..<container.childCount).reversed() {
            if let child = container.child(at: index) {
                tasks.append(.markup(child, parentID: parentID))
            }
        }
    }

    private func pushListItems(
        of list: any Markup,
        parentID: BlockID?,
        orderedStart: UInt?,
        onto tasks: inout [BlockTask]
    ) {
        guard list.childCount > 0 else { return }
        for index in (0..<list.childCount).reversed() {
            guard let item = list.child(at: index) as? ListItem else { continue }
            let kind: ListItemKind
            if let orderedStart {
                let restart = index == 0 && orderedStart != 1 ? Int(orderedStart) : nil
                kind = .ordered(restartNumber: restart)
            } else {
                kind = .unordered
            }
            tasks.append(.listItem(item, parentID: parentID, kind: kind))
        }
    }

    private func pushInlineChildren(
        of container: any Markup,
        onto tasks: inout [InlineTask]
    ) {
        guard container.childCount > 0 else { return }
        for index in (0..<container.childCount).reversed() {
            if let child = container.child(at: index) {
                tasks.append(.enter(child))
            }
        }
    }

    private static func sourceRangeCoveringWholeInput(
        _ markdown: String
    ) -> MarkdownSourceRange {
        var line = 1
        var column = 1
        var previousWasCarriageReturn = false
        for byte in markdown.utf8 {
            if byte == 0x0D {
                line += 1
                column = 1
                previousWasCarriageReturn = true
            } else if byte == 0x0A {
                if !previousWasCarriageReturn {
                    line += 1
                }
                column = 1
                previousWasCarriageReturn = false
            } else {
                column += 1
                previousWasCarriageReturn = false
            }
        }
        return MarkdownSourceRange(
            lowerBound: MarkdownSourcePosition(line: 1, utf8Column: 1),
            upperBound: MarkdownSourcePosition(line: line, utf8Column: column)
        )
    }

}
