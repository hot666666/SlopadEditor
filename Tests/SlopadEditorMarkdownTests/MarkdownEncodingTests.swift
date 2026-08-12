import SlopadCoreModel
import SlopadEditorMarkdown
import Testing

@Suite("Markdown encode")
struct MarkdownEncodingTests {
    @Test("모든 canonical block kind와 깊이 우선 tree를 Markdown으로 보존한다")
    func everyBlockKindRoundTrips() throws {
        // Given
        let quote = BlockID("quote")
        let unordered = BlockID("unordered")
        let inputs = [
            block("paragraph", content: content("plain")),
            block("heading", kind: .heading(level: .h3), content: content("heading")),
            block("quote", kind: .quote, content: content("quoted")),
            block("quote-child", parent: quote, content: content("child paragraph")),
            block("unordered", kind: .unorderedListItem, content: content("first item")),
            block(
                "nested-ordered",
                parent: unordered,
                kind: .orderedListItem(restartNumber: 3),
                content: content("nested item")
            ),
            block("todo-open", kind: .todo(isChecked: false), content: content("open")),
            block("todo-done", kind: .todo(isChecked: true), content: content("done")),
            block("code", kind: .codeBlock(language: "swift"), content: content("let x = 1\n")),
            block("divider", kind: .divider),
        ]

        // When
        let encoded = try SlopadEditorMarkdown.encode(inputs)
        let decoded = try SlopadEditorMarkdown.decode(encoded)

        // Then
        expectSemanticEquality(decoded, inputs)
        #expect(encoded.contains("### heading"))
        #expect(encoded.contains("``` swift"))
        let encodedAgain = try SlopadEditorMarkdown.encode(inputs)
        #expect(encoded == encodedAgain)
    }

    @Test("Markdown round trip은 native archive와 달리 source block ID를 보존하지 않는다")
    func roundTripCreatesFreshIDsInsteadOfPreservingSourceIdentity() throws {
        // Given
        let source = [
            block("source-root", kind: .quote, content: content("root")),
            block("source-child", parent: "source-root", content: content("child")),
        ]

        // When
        let decoded = try SlopadEditorMarkdown.decode(SlopadEditorMarkdown.encode(source))

        // Then
        #expect(Set(decoded.map(\.id)).isDisjoint(with: Set(source.map(\.id))))
        expectSemanticEquality(decoded, source)
    }

    @Test("다섯 inline mark와 교차 범위 및 code의 상위 mark를 의미적으로 보존한다")
    func nestedAndCrossingInlineMarksRoundTrip() throws {
        // Given
        let input = block(
            "inline",
            content: content(
                "a b c d e",
                marks: [
                    mark(.strong, 0, 9),
                    mark(.emphasis, 2, 9),
                    mark(.strikethrough, 4, 9),
                    mark(.link(destination: "https://e.x/a?x=1&y=2"), 6, 9),
                    mark(.code, 8, 9),
                ]
            )
        )

        // When
        let encoded = try SlopadEditorMarkdown.encode([input])
        let decoded = try SlopadEditorMarkdown.decode(encoded)

        // Then
        expectSemanticEquality(decoded, [input])
        #expect(encoded.contains("**"))
        #expect(encoded.contains("*b"))
        #expect(encoded.contains("~~"))
        #expect(encoded.contains("`"))
    }

    @Test("단독 emphasis는 결정적으로 underscore delimiter를 사용한다")
    func standaloneEmphasisUsesUnderscore() throws {
        // Given
        let input = block("emphasis", content: content("alpha", marks: [mark(.emphasis, 0, 5)]))

        // When
        let encoded = try SlopadEditorMarkdown.encode([input])
        let decoded = try SlopadEditorMarkdown.decode(encoded)

        // Then
        #expect(encoded == "_alpha_")
        expectSemanticEquality(decoded, [input])
    }

    @Test("strike seam과 Unicode 인접 경계에서는 emphasis가 별표 fallback으로 의미를 보존한다")
    func emphasisFallbackPreservesStrikeSeamAndUnicodeBoundary() throws {
        // Given
        let input = block(
            "seam",
            content: content(
                "😀xy😀",
                marks: [
                    mark(.strong, 0, 3),
                    mark(.emphasis, 1, 3),
                    mark(.strikethrough, 2, 3),
                ]
            )
        )

        // When
        let encoded = try SlopadEditorMarkdown.encode([input])
        let decoded = try SlopadEditorMarkdown.decode(encoded)

        // Then
        #expect(encoded.contains("*&#x78;"))
        #expect(!encoded.contains("~~_"))
        #expect(encoded.contains("&#x1f600;"))
        expectSemanticEquality(decoded, [input])
    }

    @Test("inline code는 backtick run과 양끝 공백을 의미적으로 보존한다")
    func inlineCodeEscapesItsDelimiterAndPreservesBoundarySpaces() throws {
        // Given
        let texts = [" `inside` ", "  "]

        // When / Then
        for (index, text) in texts.enumerated() {
            let input = block(
                "code-\(index)",
                content: content(text, marks: [mark(.code, 0, text.count)])
            )
            let encoded = try SlopadEditorMarkdown.encode([input])
            let decoded = try SlopadEditorMarkdown.decode(encoded)

            #expect(index == 0 ? encoded.hasPrefix("``") : encoded.hasPrefix("`"))
            expectSemanticEquality(decoded, [input])
        }
    }

    @Test("fenced code는 content의 더 긴 backtick run보다 긴 fence를 선택한다")
    func fencedCodeChoosesLongerBacktickFence() throws {
        // Given
        let input = block(
            "fenced",
            kind: .codeBlock(language: "swift"),
            content: content("let ticks = ```\n")
        )

        // When
        let encoded = try SlopadEditorMarkdown.encode([input])
        let decoded = try SlopadEditorMarkdown.decode(encoded)

        // Then
        #expect(encoded.hasPrefix("```` swift\n"))
        expectSemanticEquality(decoded, [input])
    }

    @Test("plain text Markdown punctuation과 hard break를 문법으로 승격하지 않는다")
    func punctuationAndHardBreaksRoundTrip() throws {
        // Given
        let input = block(
            "escape",
            content: content("* _ ` [ ] ( ) # > - + ! \\ & <tag>\nnext")
        )

        // When
        let encoded = try SlopadEditorMarkdown.encode([input])
        let decoded = try SlopadEditorMarkdown.decode(encoded)

        // Then
        expectSemanticEquality(decoded, [input])
        #expect(encoded.contains("\\*"))
        #expect(encoded.contains("\\" + "\n"))
    }

    @Test("decoder golden Markdown은 canonicalize된 encode 뒤에도 같은 의미를 가진다")
    func decodeEncodeDecodeGoldenRoundTrip() throws {
        // Given
        let markdown = """
        # Title

        > quote **strong**
        >
        > - [x] done
        >   - nested

        3. third
        4. fourth

        ```swift
        let value = `1`
        ```
        """
        let first = try SlopadEditorMarkdown.decode(markdown)

        // When
        let encoded = try SlopadEditorMarkdown.encode(first)
        let second = try SlopadEditorMarkdown.decode(encoded)

        // Then
        expectSemanticEquality(second, first)
    }

    @Test("결정적 pseudo-random mark 조합은 의미 round-trip을 보존한다")
    func propertyStyleFormattingRoundTrip() throws {
        // Given / When / Then
        var generator = DeterministicGenerator(seed: 0xC0FFEE)
        for _ in 0..<200 {
            let length = 1 + generator.nextInt(upperBound: 12)
            let text = (0..<length).map { _ in generator.nextInt(upperBound: 5) == 0 ? "😀" : "a" }.joined()
            var marks: [BlockContent.InlineMark] = []
            let lower = generator.nextInt(upperBound: length)
            let middle = lower + 1 + generator.nextInt(upperBound: length - lower)
            let upper = middle + generator.nextInt(upperBound: length - middle + 1)
            if lower < upper {
                marks.append(mark(.strong, lower, upper))
            }
            if middle < upper {
                marks.append(mark(.emphasis, middle, upper))
            }
            if middle + 1 < upper {
                marks.append(mark(.strikethrough, middle + 1, upper))
            }
            let input = block("random", content: content(text, marks: marks))

            let encoded = try SlopadEditorMarkdown.encode([input])
            let decoded = try SlopadEditorMarkdown.decode(encoded)

            expectSemanticEquality(decoded, [input])
        }
    }

    @Test("lossless Markdown이 없는 canonical shape는 partial output 없이 typed diagnostic으로 거절한다")
    func unsupportedShapesFailClosed() {
        // Given
        let parent = BlockID("parent")
        let cases: [([EditorBlockInput], MarkdownEncodingDiagnostic.Kind)] = [
            ([], .emptyDocument),
            ([
                block("parent"),
                block("child", parent: parent, kind: .heading(level: .h1)),
            ], .unsupportedChildHierarchy),
            ([
                block("code", kind: .codeBlock(language: nil), content: content("no newline")),
            ], .codeBlockRequiresTrailingLineBreak),
            ([
                block(
                    "links",
                    content: content(
                        "abc",
                        marks: [
                            mark(.link(destination: "one"), 0, 2),
                            mark(.link(destination: "two"), 1, 3),
                        ]
                    )
                ),
            ], .intersectingLinks),
            ([
                block(
                    "crossing",
                    content: content(
                        "abc",
                        marks: [mark(.strong, 0, 2), mark(.emphasis, 1, 3)]
                    )
                ),
            ], .crossingInlineMarks),
        ]

        // When / Then
        for (inputs, expectedKind) in cases {
            var captured: MarkdownEncodingError?
            do {
                _ = try SlopadEditorMarkdown.encode(inputs)
            } catch {
                captured = error
            }
            #expect(captured?.diagnostics.contains { $0.kind == expectedKind } == true)
        }
    }

    @Test("유일한 root 빈 paragraph만 decoder의 empty document와 round-trip한다")
    func soleRootEmptyParagraphRoundTrips() throws {
        // Given
        let input = block("empty")

        // When
        let encoded = try SlopadEditorMarkdown.encode([input])
        let decoded = try SlopadEditorMarkdown.decode(encoded)

        // Then
        #expect(encoded.isEmpty)
        expectSemanticEquality(decoded, [input])
    }

    @Test("root sibling 및 nested 빈 paragraph는 partial output 없이 거절한다")
    func emptyParagraphsOutsideTheSoleRootFailClosed() {
        // Given
        let quote = BlockID("quote")
        let cases: [([EditorBlockInput], BlockID)] = [
            ([
                block("text", content: content("visible")),
                block("empty-root"),
            ], BlockID("empty-root")),
            ([
                block("empty-root"),
                block("text", content: content("visible")),
            ], BlockID("empty-root")),
            ([
                block("quote", kind: .quote, content: content("owner")),
                block("empty-child", parent: quote),
            ], BlockID("empty-child")),
        ]

        // When / Then
        for (inputs, emptyParagraphID) in cases {
            var captured: MarkdownEncodingError?
            do {
                _ = try SlopadEditorMarkdown.encode(inputs)
            } catch {
                captured = error
            }

            #expect(
                captured?.diagnostics.contains {
                    $0.kind == .unrepresentableEmptyParagraph && $0.blockID == emptyParagraphID
                } == true
            )
        }
    }

    @Test("빈 quote/list container가 첫 paragraph child를 흡수하는 shape는 거절한다")
    func emptyContainersWithParagraphChildrenFailClosed() {
        // Given
        let cases: [(EditorBlockInput, EditorBlockInput)] = [
            (
                block("quote", kind: .quote),
                block(
                    "quote-child",
                    parent: BlockID("quote"),
                    content: content("child")
                )
            ),
            (
                block("unordered", kind: .unorderedListItem),
                block(
                    "unordered-child",
                    parent: BlockID("unordered"),
                    content: content("child")
                )
            ),
            (
                block("ordered", kind: .orderedListItem(restartNumber: 2)),
                block(
                    "ordered-child",
                    parent: BlockID("ordered"),
                    content: content("child")
                )
            ),
            (
                block("todo", kind: .todo(isChecked: false)),
                block(
                    "todo-child",
                    parent: BlockID("todo"),
                    content: content("child")
                )
            ),
        ]

        // When / Then
        for (container, child) in cases {
            var captured: MarkdownEncodingError?
            do {
                _ = try SlopadEditorMarkdown.encode([container, child])
            } catch {
                captured = error
            }

            #expect(
                captured?.diagnostics.contains {
                    $0.kind == .ambiguousEmptyContainer && $0.blockID == container.id
                } == true
            )
        }
    }

    private func block(
        _ id: String,
        parent: BlockID? = nil,
        kind: BlockKind = .paragraph,
        content: BlockContent = BlockContent()
    ) -> EditorBlockInput {
        EditorBlockInput(id: BlockID(id), parentID: parent, kind: kind, content: content)
    }

    private func content(
        _ text: String = "",
        marks: [BlockContent.InlineMark] = []
    ) -> BlockContent {
        BlockContent(text: text, marks: marks)
    }

    private func mark(
        _ kind: BlockContent.InlineMark.Kind,
        _ lowerBound: Int,
        _ upperBound: Int
    ) -> BlockContent.InlineMark {
        BlockContent.InlineMark(kind: kind, range: TextRange(lowerBound, upperBound))
    }

    private func expectSemanticEquality(
        _ actual: [EditorBlockInput],
        _ expected: [EditorBlockInput],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(actual.count == expected.count, sourceLocation: sourceLocation)
        guard actual.count == expected.count else { return }

        let actualIndexes = Dictionary(uniqueKeysWithValues: actual.enumerated().map { ($1.id, $0) })
        let expectedIndexes = Dictionary(uniqueKeysWithValues: expected.enumerated().map { ($1.id, $0) })
        for (actualBlock, expectedBlock) in zip(actual, expected) {
            #expect(actualBlock.kind == expectedBlock.kind, sourceLocation: sourceLocation)
            #expect(actualBlock.content == expectedBlock.content, sourceLocation: sourceLocation)
            #expect(
                actualBlock.parentID.flatMap { actualIndexes[$0] }
                    == expectedBlock.parentID.flatMap { expectedIndexes[$0] },
                sourceLocation: sourceLocation
            )
        }
    }
}

private struct DeterministicGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextInt(upperBound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Int(state % UInt64(upperBound))
    }
}
