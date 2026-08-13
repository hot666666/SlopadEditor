/// Bounds parser-owned AST nesting before constructing parser values.
struct MarkdownNestingPreflight {
    static let maximumSupportedDepth = 64

    private struct ListNestingFrame {
        var contentColumn: Int
    }

    private struct ListMarkerIndentation {
        var markerColumn: Int
        var contentColumn: Int
        var contentIndex: Substring.Index
    }

    private struct FenceDelimiter {
        var character: Character
        var count: Int
    }

    private struct ActiveFence {
        var delimiter: FenceDelimiter
        var quoteDepth: Int
        var listFrames: [ListNestingFrame]
        var minimumColumn: Int
    }

    /// Approximates block-container depth without recursion before entering swift-markdown.
    ///
    /// swift-markdown 0.8.0 can exhaust its own AST stack on adversarially deep quote or
    /// list input, so this format boundary fails closed before constructing that AST.
    static func exceedsSupportedDepth(in markdown: String) -> Bool {
        var activeQuoteDepth: Int?
        var activeFence: ActiveFence?
        var listFrames: [ListNestingFrame] = []

        for line in markdown.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        ) {
            lineProcessing: while true {
                var index = line.startIndex
                var column = 0

                if let fence = activeFence {
                    let quoteDepth = consumeQuoteMarkers(
                        in: line,
                        index: &index,
                        column: &column,
                        maximumCount: fence.quoteDepth
                    )
                    guard quoteDepth == fence.quoteDepth,
                        remainsInListContainer(
                            fence.listFrames,
                            in: line,
                            startingAt: index,
                            startingColumn: column
                        )
                    else {
                        activeFence = nil
                        continue lineProcessing
                    }
                    if isClosingFence(
                        fence.delimiter,
                        in: line,
                        startingAt: index,
                        startingColumn: column,
                        minimumColumn: fence.minimumColumn
                    ) {
                        activeFence = nil
                    }
                    break
                }

                let quoteDepth = consumeQuoteMarkers(
                    in: line,
                    index: &index,
                    column: &column
                )
                if quoteDepth > maximumSupportedDepth { return true }

                if activeQuoteDepth != quoteDepth {
                    activeQuoteDepth = quoteDepth
                    listFrames.removeAll(keepingCapacity: true)
                }

                if let minimumColumn = listFrames.last?.contentColumn,
                    let delimiter = openingFence(
                        in: line,
                        startingAt: index,
                        startingColumn: column,
                        minimumColumn: minimumColumn
                    )
                {
                    activeFence = ActiveFence(
                        delimiter: delimiter,
                        quoteDepth: quoteDepth,
                        listFrames: listFrames,
                        minimumColumn: minimumColumn
                    )
                    break
                }

                if let delimiter = openingFence(
                    in: line,
                    startingAt: index,
                    startingColumn: column,
                    minimumColumn: column
                ) {
                    listFrames.removeAll(keepingCapacity: true)
                    activeFence = ActiveFence(
                        delimiter: delimiter,
                        quoteDepth: quoteDepth,
                        listFrames: [],
                        minimumColumn: column
                    )
                    break
                }

                guard
                    let marker = listMarkerIndentation(
                        in: line,
                        startingAt: index,
                        startingColumn: column
                    )
                else {
                    break
                }

                if listFrames.isEmpty {
                    guard marker.markerColumn - column <= 3 else { break }
                    listFrames.append(ListNestingFrame(contentColumn: marker.contentColumn))
                } else if let parentIndex = listFrames.lastIndex(where: {
                    marker.markerColumn >= $0.contentColumn
                        && marker.markerColumn - $0.contentColumn <= 3
                }) {
                    listFrames.removeSubrange((parentIndex + 1)..<listFrames.endIndex)
                    listFrames.append(ListNestingFrame(contentColumn: marker.contentColumn))
                } else if marker.markerColumn - column <= 3 {
                    listFrames.removeAll(keepingCapacity: true)
                    listFrames.append(ListNestingFrame(contentColumn: marker.contentColumn))
                } else {
                    break
                }

                if quoteDepth + listFrames.count > maximumSupportedDepth { return true }

                if let delimiter = openingFence(
                    in: line,
                    startingAt: marker.contentIndex,
                    startingColumn: marker.contentColumn,
                    minimumColumn: marker.contentColumn
                ) {
                    activeFence = ActiveFence(
                        delimiter: delimiter,
                        quoteDepth: quoteDepth,
                        listFrames: listFrames,
                        minimumColumn: marker.contentColumn
                    )
                }
                break
            }
        }
        return false
    }

    private static func remainsInListContainer(
        _ listFrames: [ListNestingFrame],
        in line: Substring,
        startingAt startIndex: Substring.Index,
        startingColumn: Int
    ) -> Bool {
        guard let contentColumn = listFrames.last?.contentColumn else { return true }

        var index = startIndex
        var column = startingColumn
        consumeIndentation(
            in: line,
            index: &index,
            column: &column,
            maximum: nil
        )
        return index == line.endIndex || column >= contentColumn
    }

    private static func consumeQuoteMarkers(
        in line: Substring,
        index: inout Substring.Index,
        column: inout Int,
        maximumCount: Int? = nil
    ) -> Int {
        var depth = 0
        while index < line.endIndex,
            maximumCount.map({ depth < $0 }) ?? true
        {
            let checkpoint = index
            let checkpointColumn = column
            consumeIndentation(
                in: line,
                index: &index,
                column: &column,
                maximum: 3
            )
            guard index < line.endIndex, line[index] == ">" else {
                index = checkpoint
                column = checkpointColumn
                break
            }
            depth += 1
            index = line.index(after: index)
            column += 1
            if index < line.endIndex, line[index] == " " {
                index = line.index(after: index)
                column += 1
            }
        }
        return depth
    }

    private static func openingFence(
        in line: Substring,
        startingAt startIndex: Substring.Index,
        startingColumn: Int,
        minimumColumn: Int
    ) -> FenceDelimiter? {
        var index = startIndex
        var column = startingColumn
        consumeIndentation(
            in: line,
            index: &index,
            column: &column,
            maximum: nil
        )
        guard column >= minimumColumn, column - minimumColumn <= 3,
            index < line.endIndex,
            line[index] == "`" || line[index] == "~"
        else { return nil }

        let character = line[index]
        var count = 0
        while index < line.endIndex, line[index] == character {
            count += 1
            index = line.index(after: index)
        }
        guard count >= 3 else { return nil }
        if character == "`", line[index...].contains("`") {
            return nil
        }
        return FenceDelimiter(character: character, count: count)
    }

    private static func isClosingFence(
        _ delimiter: FenceDelimiter,
        in line: Substring,
        startingAt startIndex: Substring.Index,
        startingColumn: Int,
        minimumColumn: Int
    ) -> Bool {
        var index = startIndex
        var column = startingColumn
        consumeIndentation(
            in: line,
            index: &index,
            column: &column,
            maximum: nil
        )
        guard column >= minimumColumn, column - minimumColumn <= 3 else { return false }

        var count = 0
        while index < line.endIndex, line[index] == delimiter.character {
            count += 1
            index = line.index(after: index)
        }
        guard count >= delimiter.count else { return false }
        return line[index...].allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func listMarkerIndentation(
        in line: Substring,
        startingAt startIndex: Substring.Index,
        startingColumn: Int
    ) -> ListMarkerIndentation? {
        var index = startIndex
        var column = startingColumn
        consumeIndentation(
            in: line,
            index: &index,
            column: &column,
            maximum: nil
        )
        let markerColumn = column
        guard index < line.endIndex else { return nil }

        let markerWidth: Int
        if line[index] == "-" || line[index] == "+" || line[index] == "*" {
            markerWidth = 1
            index = line.index(after: index)
        } else {
            var digitCount = 0
            while index < line.endIndex,
                line[index].isASCII,
                line[index].isNumber,
                digitCount < 9
            {
                digitCount += 1
                index = line.index(after: index)
            }
            guard digitCount > 0, index < line.endIndex,
                line[index] == "." || line[index] == ")"
            else { return nil }
            markerWidth = digitCount + 1
            index = line.index(after: index)
        }

        guard index == line.endIndex || line[index] == " " || line[index] == "\t" else {
            return nil
        }

        var followingColumns = 0
        while index < line.endIndex,
            line[index] == " " || line[index] == "\t",
            followingColumns < 4
        {
            if line[index] == "\t" {
                followingColumns += 4 - ((markerColumn + markerWidth + followingColumns) % 4)
            } else {
                followingColumns += 1
            }
            index = line.index(after: index)
        }
        if followingColumns == 0 {
            followingColumns = 1
        }
        return ListMarkerIndentation(
            markerColumn: markerColumn,
            contentColumn: markerColumn + markerWidth + followingColumns,
            contentIndex: index
        )
    }

    private static func consumeIndentation(
        in line: Substring,
        index: inout Substring.Index,
        column: inout Int,
        maximum: Int?
    ) {
        var consumed = 0
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            let width = line[index] == "\t" ? 4 - (column % 4) : 1
            guard maximum.map({ consumed + width <= $0 }) ?? true else { break }
            consumed += width
            column += width
            index = line.index(after: index)
        }
    }
}
