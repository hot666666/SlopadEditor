import SlopadCoreModel
import SlopadEditorMarkdown
import Testing

@Suite("Markdown inline decode")
struct MarkdownInlineDecodingTests {
    @Test("중첩 mark는 emoji와 결합 문자를 grapheme 단위의 정확한 범위로 보존한다")
    func nestedMarksUseExactGraphemeRanges() throws {
        // Given
        let markdown = "**a *😀e\u{301}* z**"

        // When
        let content = try #require(SlopadEditorMarkdown.decode(markdown).first).content

        // Then
        #expect(content.text == "a 😀e\u{301} z")
        #expect(
            content.marks == [
                mark(.strong, 0, 6),
                mark(.emphasis, 2, 4),
            ])
    }

    @Test("AST fragment가 grapheme을 가르면 mark를 atomic Character 전체로 확장한다")
    func splitGraphemeMarksNormalizeOutwardToAtomicCharacters() throws {
        // Given
        let cases = [
            ("e**\u{301}**", "e\u{301}"),
            ("**e**\u{301}", "e\u{301}"),
            ("👩**\u{200D}💻**", "👩\u{200D}💻"),
            ("**👩**\u{200D}💻", "👩\u{200D}💻"),
            ("🇰**🇷**", "🇰🇷"),
            ("**🇰**🇷", "🇰🇷"),
        ]

        // When / Then
        for (markdown, expectedText) in cases {
            let content = try #require(SlopadEditorMarkdown.decode(markdown).first).content
            let normalizedAgain = BlockContent(text: content.text, marks: content.marks)

            #expect(content.text == expectedText)
            #expect(content.text.count == 1)
            #expect(content.marks == [mark(.strong, 0, 1)])
            #expect(normalizedAgain.marks == content.marks)
        }
    }

    @Test("하나의 AST fragment 안에 있는 combining ZWJ와 flag mark 범위는 그대로 보존한다")
    func completeGraphemeMarksKeepExactRanges() throws {
        // Given
        let markdown = "**e\u{301}** **👩\u{200D}💻** **🇰🇷**"

        // When
        let content = try #require(SlopadEditorMarkdown.decode(markdown).first).content
        let normalizedAgain = BlockContent(text: content.text, marks: content.marks)

        // Then
        #expect(content.text == "e\u{301} 👩\u{200D}💻 🇰🇷")
        #expect(
            content.marks == [
                mark(.strong, 0, 1),
                mark(.strong, 2, 3),
                mark(.strong, 4, 5),
            ])
        #expect(normalizedAgain.marks == content.marks)
    }

    @Test("인접한 같은 mark는 adapter가 canonical 범위 하나로 병합한다")
    func adjacentEquivalentMarksAreCanonicalized() throws {
        // Given
        let markdown = "[a](same)[b](same)"

        // When
        let content = try #require(SlopadEditorMarkdown.decode(markdown).first).content

        // Then
        #expect(content.text == "ab")
        #expect(content.marks == [mark(.link(destination: "same"), 0, 2)])
    }

    @Test("strong emphasis strike와 inline code를 canonical mark로 변환한다")
    func allSupportedFormattingMarksDecode() throws {
        // Given
        let markdown = "**s** *e* ~~x~~ `c`"

        // When
        let content = try #require(SlopadEditorMarkdown.decode(markdown).first).content

        // Then
        #expect(content.text == "s e x c")
        #expect(
            content.marks == [
                mark(.strong, 0, 1),
                mark(.emphasis, 2, 3),
                mark(.strikethrough, 4, 5),
                mark(.code, 6, 7),
            ])
    }

    @Test("soft break는 공백이고 hard line break는 개행이다")
    func softAndHardBreaksRemainDistinct() throws {
        // Given
        let markdown = "soft\nbreak  \nhard"

        // When
        let content = try #require(SlopadEditorMarkdown.decode(markdown).first).content

        // Then
        #expect(content.text == "soft break\nhard")
    }

    @Test("escape와 entity는 parser가 해석한 text 의미로 변환한다")
    func escapesAndEntitiesDecodeToTextMeaning() throws {
        // Given
        let markdown = #"\*literal\* &amp; &#x1F600;"#

        // When
        let content = try #require(SlopadEditorMarkdown.decode(markdown).first).content

        // Then
        #expect(content.text == "*literal* & 😀")
        #expect(content.marks.isEmpty)
    }

    @Test("smart punctuation을 끄고 입력의 straight punctuation을 보존한다")
    func smartPunctuationIsDisabled() throws {
        // Given
        let markdown = #""quote" -- dash"#

        // When
        let content = try #require(SlopadEditorMarkdown.decode(markdown).first).content

        // Then
        #expect(content.text == #""quote" -- dash"#)
    }

    @Test("빈 destination과 autolink 및 reference link를 link mark로 보존한다")
    func destinationOnlyAutolinkAndReferenceLinksDecode() throws {
        // Given
        let markdown = "[empty]() <https://e.x> [ref][id]\n\n[id]: /target"

        // When
        let content = try #require(SlopadEditorMarkdown.decode(markdown).first).content

        // Then
        #expect(content.text == "empty https://e.x ref")
        #expect(
            content.marks == [
                mark(.link(destination: ""), 0, 5),
                mark(.link(destination: "https://e.x"), 6, 17),
                mark(.link(destination: "/target"), 18, 21),
            ])
    }

    @Test("link 안의 formatting은 link와 formatting 범위를 모두 보존한다")
    func linkCanContainSupportedFormatting() throws {
        // Given
        let markdown = "[**go**](destination)"

        // When
        let content = try #require(SlopadEditorMarkdown.decode(markdown).first).content

        // Then
        #expect(content.text == "go")
        #expect(
            Set(content.marks)
                == Set([
                    mark(.link(destination: "destination"), 0, 2),
                    mark(.strong, 0, 2),
                ]))
    }

    private func mark(
        _ kind: BlockContent.InlineMark.Kind,
        _ lowerBound: Int,
        _ upperBound: Int
    ) -> BlockContent.InlineMark {
        BlockContent.InlineMark(
            kind: kind,
            range: TextRange(lowerBound, upperBound)
        )
    }
}
