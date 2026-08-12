import Testing

import SlopadCoreModel
import SlopadEditorDocumentModel

@Suite("EditorModel inline style 명령")
struct EditorModelInlineStyleCommandTests {
    @Test("applyTextStyle 명령은 지정 범위에 inline style을 적용한다")
    func givenPlainTextRange_whenApplyTextStyleRuns_thenInlineStyleIsApplied() {
        // Given
        let blockID: BlockID = "block"
        let editor = EditorModel(
            document: .singleParagraph("Hello", id: blockID),
            selection: .caret(blockID: blockID, offset: 0)
        )
        let expectedMarks = [BlockContent.InlineMark(kind: .strong, range: TextRange(1, 4))]

        // When
        _ = editor.apply(
            .applyTextStyle(blockID: blockID, range: TextRange(1, 4), style: .strong)
        )

        // Then
        #expect(editor.document.blocks[blockID]?.content.marks == expectedMarks)
    }

    @Test("clearTextStyles 명령은 지정 범위를 plain text로 만든다")
    func givenStyledTextRange_whenClearTextStylesRuns_thenRangeBecomesPlainText() throws {
        // Given
        let blockID: BlockID = "block"
        var document = Document.singleParagraph("Hello", id: blockID)
        try document.replaceContent(
            blockID: blockID,
            content: BlockContent(
                text: "Hello",
                marks: [
                    BlockContent.InlineMark(kind: .strong, range: TextRange(0, 5)),
                    BlockContent.InlineMark(kind: .emphasis, range: TextRange(1, 4)),
                ]
            )
        ).get()
        let editor = EditorModel(
            document: document,
            selection: .caret(blockID: blockID, offset: 0)
        )
        let expectedMarks = [
            BlockContent.InlineMark(kind: .strong, range: TextRange(0, 1)),
            BlockContent.InlineMark(kind: .strong, range: TextRange(4, 5)),
        ]

        // When
        _ = editor.apply(.clearTextStyles(blockID: blockID, range: TextRange(1, 4)))

        // Then
        #expect(editor.document.blocks[blockID]?.content.marks == expectedMarks)
    }
}
