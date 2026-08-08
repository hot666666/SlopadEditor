import SlopadCoreModel
import Testing

@testable import SlopadEditorModel

@Suite("inline Markdown 입력 규칙")
struct InlineMarkdownInputRuleTests {
    @Test("완성된 inline 문법은 source delimiter 없이 canonical mark와 텍스트가 된다")
    func convertsEverySupportedPattern() {
        // Given
        let cases: [(source: String, text: String, marks: [BlockContent.InlineMark])] = [
            ("**bold**", "bold", [mark(.strong, 0, 4)]),
            ("*italic*", "italic", [mark(.emphasis, 0, 6)]),
            ("_italic_", "italic", [mark(.emphasis, 0, 6)]),
            ("`code`", "code", [mark(.code, 0, 4)]),
            ("~~strike~~", "strike", [mark(.strikethrough, 0, 6)]),
            ("[label](https://e.x)", "label", [mark(.link(destination: "https://e.x"), 0, 5)]),
            ("[x](a(b))", "x", [mark(.link(destination: "a(b)"), 0, 1)]),
            ("***bold***", "bold", [mark(.strong, 0, 4), mark(.emphasis, 0, 4)]),
        ]

        for entry in cases {
            let editor = makeEditor()

            // When
            type(entry.source, into: editor)

            // Then
            #expect(editor.document.block("block")?.content == BlockContent(text: entry.text, marks: entry.marks))
            #expect(editor.selection == .caret(blockID: "block", offset: entry.text.count))
        }
    }

    @Test("불완전하거나 escape 및 공백 인접인 문법은 literal로 남는다")
    func rejectsIncompleteEscapedAndWhitespaceAdjacentCandidates() {
        // Given
        let rejected = [
            "**bold",
            "*",
            "[label](",
            "** **",
            "\\*bold\\*",
            "a * b *",
            "[ label](url)",
            "[label](bad url)",
        ]

        for source in rejected {
            let editor = makeEditor()

            // When
            type(source, into: editor)

            // Then
            #expect(editor.document.block("block")?.content == BlockContent(text: source), "\(source)는 literal이어야 한다")
        }
    }

    @Test("code span 안 delimiter는 변환되지 않고 span 자체만 code mark가 된다")
    func rejectsDelimiterInsideCodeSpan() {
        // Given
        let editor = makeEditor()

        // When
        type("`*literal*`", into: editor)

        // Then
        #expect(editor.document.block("block")?.content == BlockContent(
            text: "*literal*",
            marks: [mark(.code, 0, 9)]
        ))
    }

    @Test("다른 길이 backtick은 literal이고 같은 길이 run만 code span을 닫는다")
    func matchesExactBacktickRunLength() {
        // Given
        let completed = makeEditor()
        let incomplete = makeEditor()

        // When
        type("``code ` *literal*``", into: completed)
        type("``code ` *literal*", into: incomplete)

        // Then
        #expect(completed.document.block("block")?.content == BlockContent(
            text: "code ` *literal*",
            marks: [mark(.code, 0, 16)]
        ))
        #expect(incomplete.document.block("block")?.content == BlockContent(text: "``code ` *literal*"))
    }

    @Test("nested syntax는 안쪽부터 변환해도 mark와 caret이 보존된다")
    func convertsNestedSyntaxSequentially() {
        // Given
        let editor = makeEditor()

        // When
        type("**bold and _italic_**", into: editor)

        // Then
        #expect(editor.document.block("block")?.content == BlockContent(
            text: "bold and italic",
            marks: [
                mark(.strong, 0, 15),
                mark(.emphasis, 9, 15),
            ]
        ))
        #expect(editor.selection == .caret(blockID: "block", offset: 15))
    }

    @Test("한글 문장도 grapheme offset mark로 변환한다")
    func convertsKoreanText() {
        // Given
        let editor = makeEditor()

        // When
        type("문장 **강조** 끝", into: editor)

        // Then
        #expect(editor.document.block("block")?.content == BlockContent(
            text: "문장 강조 끝",
            marks: [mark(.strong, 3, 5)]
        ))
        #expect(editor.selection == .caret(blockID: "block", offset: 7))
    }

    @Test("완성 delimiter 입력과 변환은 undo 한 번에 함께 되돌린다")
    func undoRestoresStateBeforeClosingDelimiter() {
        // Given
        let editor = makeEditor()
        type("**bold*", into: editor)

        // When
        _ = editor.apply(.insertText("*"))
        _ = editor.undo()

        // Then
        #expect(editor.document.block("block")?.content == BlockContent(text: "**bold*"))
        #expect(editor.selection == .caret(blockID: "block", offset: 7))
    }

    @Test("긴 문단 중간에서도 candidate window만 보고 inline syntax를 변환한다")
    func keepsCandidateBoundedForMidParagraphTyping() {
        // Given
        let prefix = String(repeating: "가", count: 2_000)
        let suffix = String(repeating: "나", count: 2_000)
        let editor = EditorModel(
            document: Document(blockInputs: [
                EditorBlockInput(id: "block", content: BlockContent(text: prefix + "**bold*" + suffix))
            ]),
            selection: .caret(blockID: "block", offset: prefix.count + 7)
        )
        var content = BlockContent(text: String(repeating: "x", count: 10_000))

        // When
        let candidate = content.insert(
            "*", at: 5_000, capturingInputRuleCandidateWithMaximumLookback: 64
        )
        _ = editor.apply(.insertText("*"))

        // Then
        #expect(candidate?.text.count ?? .max <= 65)
        #expect(candidate?.caretOffset ?? .max <= 64)
        #expect(candidate?.baseOffset == 4_937)
        #expect(editor.document.block("block")?.content.text == prefix + "bold" + suffix)
        #expect(editor.document.block("block")?.content.marks == [mark(.strong, prefix.count, prefix.count + 4)])
        #expect(editor.selection == .caret(blockID: "block", offset: prefix.count + 4))
    }

    // MARK: - Support

    private func type(_ text: String, into editor: EditorModel) {
        for character in text {
            _ = editor.apply(.insertText(String(character)))
        }
    }

    private func makeEditor() -> EditorModel {
        EditorModel(
            document: Document(blockInputs: [EditorBlockInput(id: "block")]),
            selection: .caret(blockID: "block", offset: 0)
        )
    }

    private func mark(
        _ kind: BlockContent.InlineMark.Kind,
        _ lowerBound: Int,
        _ upperBound: Int
    ) -> BlockContent.InlineMark {
        BlockContent.InlineMark(kind: kind, range: TextRange(lowerBound, upperBound))
    }
}
