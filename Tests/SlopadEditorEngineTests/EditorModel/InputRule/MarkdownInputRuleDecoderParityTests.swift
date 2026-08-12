import SlopadCoreModel
import SlopadEditorMarkdown
import Testing

@testable import SlopadEditorDocumentModel

@Suite("inline Markdown 입력 규칙 decoder 교차 검증")
struct MarkdownInputRuleDecoderParityTests {
    @Test("완성 입력의 canonical content는 Markdown decoder와 일치한다")
    func matchesDecoderForSupportedLocalSyntax() throws {
        // Given
        let sources = [
            "**bold**",
            "*italic*",
            "_italic_",
            "`code`",
            "~~strike~~",
            "[label](https://e.x)",
            "[x](a(b))",
            "[x](a\\(b\\))",
            "***bold***",
            "**bold and _italic_**",
            "``code ` *literal*``",
            "문장 **강조** 끝",
        ]

        for source in sources {
            let editor = EditorModel(
                document: Document(blockInputs: [EditorBlockInput(id: "block")]),
                selection: .caret(blockID: "block", offset: 0)
            )

            // When
            for character in source {
                _ = editor.apply(.insertText(String(character)))
            }
            let decoded = try #require(SlopadEditorMarkdown.decode(source).first?.content)

            // Then
            #expect(editor.document.block("block")?.content == decoded, "\(source)의 input/decode 결과가 달라졌다")
        }
    }
}
