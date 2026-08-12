import SlopadEditorCoreModel
import Testing

@testable import SlopadEditorMarkdown

@Suite("Markdown block decode")
struct MarkdownBlockDecodingTests {
    @Test("빈 입력과 공백 입력은 빈 문단 하나로 변환한다")
    func emptyAndWhitespaceInputsProduceOneEmptyParagraph() throws {
        // Given
        let inputs = ["", "   \t\n\r\n"]

        // When / Then
        for markdown in inputs {
            let blocks = try SlopadEditorMarkdown.decode(markdown)
            #expect(blocks.count == 1)
            #expect(blocks[0].parentID == nil)
            #expect(blocks[0].kind == .paragraph)
            #expect(blocks[0].content == BlockContent())
        }
    }

    @Test("문단과 h1부터 h3까지의 제목을 원본 순서로 변환한다")
    func paragraphAndSupportedHeadingsDecodeInOrder() throws {
        // Given
        let markdown = "plain\n\n# one\n\n## two\n\n### three"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(
            blocks.map(\.kind) == [
                .paragraph,
                .heading(level: .h1),
                .heading(level: .h2),
                .heading(level: .h3),
            ])
        #expect(blocks.map(\.content.text) == ["plain", "one", "two", "three"])
    }

    @Test("인용의 첫 문단은 인용 내용이 되고 이후 블록은 자식이 된다")
    func quoteUsesFirstParagraphAsContentAndLaterBlocksAsChildren() throws {
        // Given
        let markdown = "> first\n>\n> second\n>\n> - nested"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        let quote = try #require(blocks.first)
        #expect(blocks.count == 3)
        #expect(quote.kind == .quote)
        #expect(quote.content.text == "first")
        #expect(blocks[1].parentID == quote.id)
        #expect(blocks[1].kind == .paragraph)
        #expect(blocks[1].content.text == "second")
        #expect(blocks[2].parentID == quote.id)
        #expect(blocks[2].kind == .unorderedListItem)
    }

    @Test("첫 블록이 문단이 아닌 인용은 빈 인용을 만들고 모든 블록을 자식으로 둔다")
    func nonParagraphFirstQuoteKeepsEmptyQuoteParent() throws {
        // Given
        let markdown = "> - child"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .quote)
        #expect(blocks[0].content.text.isEmpty)
        #expect(blocks[1].kind == .unorderedListItem)
        #expect(blocks[1].parentID == blocks[0].id)
    }

    @Test("목록 항목의 첫 문단은 항목 내용이 되고 뒤 블록은 자식이 된다")
    func listItemUsesFirstParagraphAsContentAndLaterBlocksAsChildren() throws {
        // Given
        let markdown = "- parent\n\n  child paragraph\n\n  - nested"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        let item = try #require(blocks.first)
        #expect(blocks.count == 3)
        #expect(item.kind == .unorderedListItem)
        #expect(item.content.text == "parent")
        #expect(blocks[1].parentID == item.id)
        #expect(blocks[1].kind == .paragraph)
        #expect(blocks[2].parentID == item.id)
        #expect(blocks[2].kind == .unorderedListItem)
    }

    @Test("첫 블록이 문단이 아닌 목록 항목은 빈 항목을 만들고 블록을 자식으로 둔다")
    func nonParagraphFirstListItemKeepsEmptyItemParent() throws {
        // Given
        let markdown = "- > quoted"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .unorderedListItem)
        #expect(blocks[0].content.text.isEmpty)
        #expect(blocks[1].kind == .quote)
        #expect(blocks[1].content.text == "quoted")
        #expect(blocks[1].parentID == blocks[0].id)
    }

    @Test("순서 목록의 1이 아닌 시작 번호는 첫 항목에만 restart로 기록한다")
    func orderedListRestartAppliesOnlyToFirstItemAndKeepsNesting() throws {
        // Given
        let markdown = "3. first\n4. second\n   - child"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(blocks.count == 3)
        #expect(blocks[0].kind == .orderedListItem(restartNumber: 3))
        #expect(blocks[1].kind == .orderedListItem(restartNumber: nil))
        #expect(blocks[2].kind == .unorderedListItem)
        #expect(blocks[2].parentID == blocks[1].id)
    }

    @Test("1로 시작하는 순서 목록은 restart를 기록하지 않는다")
    func defaultOrderedListStartHasNoRestart() throws {
        // Given
        let markdown = "1. first\n2. second"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(
            blocks.map(\.kind) == [
                .orderedListItem(restartNumber: nil),
                .orderedListItem(restartNumber: nil),
            ])
    }

    @Test("GFM 비순서 task 항목은 checked 상태를 보존한 todo가 된다")
    func unorderedTasksBecomeTodos() throws {
        // Given
        let markdown = "- [x] done\n- [ ] pending\n- plain"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(
            blocks.map(\.kind) == [
                .todo(isChecked: true),
                .todo(isChecked: false),
                .unorderedListItem,
            ])
        #expect(blocks.map(\.content.text) == ["done", "pending", "plain"])
    }

    @Test("fenced와 indented code 및 구분선을 canonical block으로 변환한다")
    func codeBlocksAndDividerDecode() throws {
        // Given
        let markdown = "```swift\nlet value = 1\n```\n\n    indented\n\n---"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(blocks.count == 3)
        #expect(blocks[0].kind == .codeBlock(language: "swift"))
        #expect(blocks[0].content.text == "let value = 1\n")
        #expect(blocks[1].kind == .codeBlock(language: nil))
        #expect(blocks[1].content.text == "indented\n")
        #expect(blocks[2].kind == .divider)
        #expect(blocks[2].content.text.isEmpty)
    }

    @Test("fenced code 내부의 깊은 quote와 list marker는 nesting으로 세지 않는다")
    func fencedCodeLiteralsDoNotCountTowardNesting() throws {
        // Given
        let quoteLiteral = String(repeating: "> ", count: 65) + "literal"
        let listLiteral = nestedListMarkdown(depth: 65)
        let cases = [
            "  ````text\n```\n````not-close\n\(quoteLiteral)\n\(listLiteral)\n  `````",
            "~~~text\n```\n~~~~not-close\n\(quoteLiteral)\n\(listLiteral)\n~~~~",
        ]

        // When / Then
        for markdown in cases {
            let block = try #require(SlopadEditorMarkdown.decode(markdown).first)
            #expect(block.kind == .codeBlock(language: "text"))
            #expect(block.content.text.contains(quoteLiteral))
            #expect(block.content.text.contains("level 64"))
        }
    }

    @Test("CommonMark fence가 아닌 opener는 뒤의 깊은 quote를 숨기지 않는다")
    func invalidFenceOpenerDoesNotHideDeepNesting() throws {
        // Given
        let deepQuote = String(repeating: "> ", count: 65) + "deep"
        let inputs = [
            "```bad`info\n\(deepQuote)",
            "    ```\n\(deepQuote)",
        ]

        // When / Then
        for markdown in inputs {
            var captured: MarkdownDecodingError?
            do {
                _ = try SlopadEditorMarkdown.decode(markdown)
            } catch {
                captured = error
            }
            #expect(
                try #require(captured).diagnostics.first?.kind
                    == .excessiveNesting(maximumDepth: 64)
            )
        }
    }

    @Test("quote와 list 안의 fence도 container prefix 뒤 marker를 literal로 유지한다")
    func containerFencesKeepDeepMarkersLiteral() throws {
        // Given
        let quoteLiteral = String(repeating: "> ", count: 65) + "literal"
        let quoteMarkdown = "> ```\n> \(quoteLiteral)\n> ```"
        let listMarkdown = "- parent\n\n  ```\n  \(quoteLiteral)\n  ```\n\n  - nested"

        // When
        let quoteBlocks = try SlopadEditorMarkdown.decode(quoteMarkdown)
        let listBlocks = try SlopadEditorMarkdown.decode(listMarkdown)

        // Then
        #expect(quoteBlocks.map(\.kind) == [.quote, .codeBlock(language: nil)])
        #expect(quoteBlocks[1].parentID == quoteBlocks[0].id)
        #expect(quoteBlocks[1].content.text.contains(quoteLiteral))
        #expect(
            listBlocks.map(\.kind) == [
                .unorderedListItem,
                .codeBlock(language: nil),
                .unorderedListItem,
            ])
        #expect(listBlocks[1].parentID == listBlocks[0].id)
        #expect(listBlocks[2].parentID == listBlocks[0].id)
    }

    @Test("container fence가 끝난 뒤 root의 깊은 중첩도 preflight가 거절한다")
    func implicitContainerFenceCloseDoesNotHideRootNesting() throws {
        // Given
        let deepQuote = String(repeating: "> ", count: 65) + "deep"
        let deepList = nestedListMarkdown(depth: 65)
        let inputs = [
            "> ```\n> literal\n\(deepList)",
            "- parent\n\n  ```\n  literal\n\(deepQuote)",
        ]

        // When / Then
        for markdown in inputs {
            var captured: MarkdownDecodingError?
            do {
                _ = try SlopadEditorMarkdown.decode(markdown)
            } catch {
                captured = error
            }
            #expect(
                try #require(captured).diagnostics.first?.kind
                    == .excessiveNesting(maximumDepth: 64)
            )
        }
    }

    @Test("container fence의 CRLF와 더 긴 closer 및 root EOF fence를 유지한다")
    func containerFencesKeepCRLFLongerClosersAndRootEOFBehavior() throws {
        // Given
        let deepQuote = String(repeating: "> ", count: 65) + "literal"
        let quoteMarkdown = "> ````\r\n> \(deepQuote)\r\n> `````"
        let listMarkdown = "- parent\r\n\r\n  ~~~~\r\n  \(deepQuote)\r\n  ~~~~~"
        let rootUnclosedFence = "```\n\(deepQuote)"

        // When
        let quoteBlocks = try SlopadEditorMarkdown.decode(quoteMarkdown)
        let listBlocks = try SlopadEditorMarkdown.decode(listMarkdown)
        let rootBlocks = try SlopadEditorMarkdown.decode(rootUnclosedFence)

        // Then
        #expect(quoteBlocks.map(\.kind) == [.quote, .codeBlock(language: nil)])
        #expect(quoteBlocks[1].content.text.contains(deepQuote))
        #expect(listBlocks.map(\.kind) == [.unorderedListItem, .codeBlock(language: nil)])
        #expect(listBlocks[1].content.text.contains(deepQuote))
        #expect(rootBlocks.map(\.kind) == [.codeBlock(language: nil)])
        #expect(rootBlocks[0].content.text.contains(deepQuote))
    }

    @Test("indented code 내부의 깊은 marker literal은 nesting으로 세지 않는다")
    func indentedCodeLiteralsDoNotCountTowardNesting() throws {
        // Given
        let quoteLiteral = String(repeating: "> ", count: 65) + "literal"
        let listLiteral = nestedListMarkdown(depth: 65)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")
        let markdown = "    \(quoteLiteral)\n\(listLiteral)"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .codeBlock(language: nil))
        #expect(blocks[0].content.text.contains(quoteLiteral))
    }

    @Test("list item의 indented code도 깊은 marker literal을 nesting으로 세지 않는다")
    func listIndentedCodeLiteralsDoNotCountTowardNesting() throws {
        // Given
        let quoteLiteral = String(repeating: "> ", count: 65) + "literal"
        let listLiteral = nestedListMarkdown(depth: 65)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "      \($0)" }
            .joined(separator: "\n")
        let markdown = "- parent\n\n      \(quoteLiteral)\n\(listLiteral)"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .unorderedListItem)
        #expect(blocks[1].kind == .codeBlock(language: nil))
        #expect(blocks[1].parentID == blocks[0].id)
        #expect(blocks[1].content.text.contains(quoteLiteral))
    }

    @Test("출력은 모든 부모가 자식보다 먼저인 정확한 깊이 우선 순서다")
    func outputIsExactParentBeforeChildDepthFirstOrder() throws {
        // Given
        let markdown = "> quote\n>\n> - one\n>   - nested\n> - two\n\nafter"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(blocks.map(\.content.text) == ["quote", "one", "nested", "two", "after"])
        let indexes = Dictionary(uniqueKeysWithValues: blocks.enumerated().map { ($1.id, $0) })
        for block in blocks {
            if let parentID = block.parentID {
                #expect(try #require(indexes[parentID]) < #require(indexes[block.id]))
            }
        }
    }

    @Test("각 decode 호출은 같은 Markdown에도 새로운 block ID를 만든다")
    func eachDecodeCreatesFreshBlockIDs() throws {
        // Given
        let markdown = "one\n\n- two"

        // When
        let first = try SlopadEditorMarkdown.decode(markdown)
        let second = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(first.map(\.id) != second.map(\.id))
        #expect(first.map(\.kind) == second.map(\.kind))
        #expect(first.map(\.content) == second.map(\.content))
    }

    @Test("reference definition만 있는 입력도 비어 있지 않은 성공 문서를 만든다")
    func referenceDefinitionOnlyProducesOneEmptyParagraph() throws {
        // Given
        let markdown = "[target]: https://example.com"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(blocks.count == 1)
        #expect(blocks[0].parentID == nil)
        #expect(blocks[0].kind == .paragraph)
        #expect(blocks[0].content == BlockContent())
    }

    @Test("매우 깊은 Markdown 중첩은 parser stack trap 전에 typed 진단으로 거절한다")
    func deeplyNestedMarkdownFailsClosedBeforeParserStackTrap() throws {
        // Given
        let markdown = String(repeating: "> ", count: 500) + "deep"

        // When
        var captured: MarkdownDecodingError?
        do {
            _ = try SlopadEditorMarkdown.decode(markdown)
        } catch {
            captured = error
        }

        // Then
        let error = try #require(captured)
        #expect(error.diagnostics.count == 1)
        #expect(
            error.diagnostics[0].kind
                == .excessiveNesting(maximumDepth: 64)
        )
        #expect(
            error.diagnostics[0].sourceRange.lowerBound
                == MarkdownSourcePosition(line: 1, utf8Column: 1)
        )
        #expect(
            error.diagnostics[0].sourceRange.upperBound
                == MarkdownSourcePosition(line: 1, utf8Column: 1_005)
        )
    }

    @Test("CR line ending의 preflight 진단도 whole-input line과 UTF8 column을 사용한다")
    func preflightWholeInputRangeHandlesCarriageReturn() throws {
        // Given
        let markdown = "first\r" + String(repeating: "> ", count: 500) + "deep"
        var captured: MarkdownDecodingError?

        // When
        do {
            _ = try SlopadEditorMarkdown.decode(markdown)
        } catch {
            captured = error
        }

        // Then
        let error = try #require(captured)
        #expect(error.diagnostics.count == 1)
        #expect(
            error.diagnostics[0].sourceRange
                == MarkdownSourceRange(
                    lowerBound: MarkdownSourcePosition(line: 1, utf8Column: 1),
                    upperBound: MarkdownSourcePosition(line: 2, utf8Column: 1_005)
                )
        )
    }

    @Test("허용 경계의 깊은 block quote는 iterative DFS로 변환한다")
    func deeplyNestedQuoteAtLimitDecodesIteratively() throws {
        // Given
        let markdown = String(repeating: "> ", count: 64) + "deep"

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(blocks.count == 64)
        #expect(blocks.last?.content.text == "deep")
        for index in blocks.indices.dropFirst() {
            #expect(blocks[index].parentID == blocks[index - 1].id)
        }
    }

    @Test("허용 경계 안의 깊은 nested list는 iterative DFS로 변환한다")
    func deeplyNestedListWithinLimitDecodesIteratively() throws {
        // Given
        let markdown = nestedListMarkdown(depth: 64)

        // When
        let blocks = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(blocks.count == 64)
        #expect(blocks.map(\.content.text) == (0..<64).map { "level \($0)" })
        for index in blocks.indices.dropFirst() {
            #expect(blocks[index].parentID == blocks[index - 1].id)
        }
    }

    @Test("매우 깊은 nested list도 parser stack trap 전에 typed 진단으로 거절한다")
    func deeplyNestedListFailsClosedBeforeParserStackTrap() throws {
        // Given
        let markdown = nestedListMarkdown(depth: 500)
        var captured: MarkdownDecodingError?

        // When
        do {
            _ = try SlopadEditorMarkdown.decode(markdown)
        } catch {
            captured = error
        }

        // Then
        let error = try #require(captured)
        #expect(error.diagnostics.count == 1)
        #expect(
            error.diagnostics[0].kind
                == .excessiveNesting(maximumDepth: 64)
        )
    }

    private func nestedListMarkdown(depth: Int) -> String {
        (0..<depth)
            .map { level in
                String(repeating: "  ", count: level) + "- level \(level)"
            }
            .joined(separator: "\n")
    }
}
