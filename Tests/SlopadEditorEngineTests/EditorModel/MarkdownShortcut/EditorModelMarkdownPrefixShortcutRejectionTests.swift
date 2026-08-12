import Testing

import SlopadCoreModel
import SlopadEditorDocumentModel

@Suite("EditorModel 마크다운 prefix shortcut 거부")
struct EditorModelMarkdownPrefixShortcutRejectionTests {
    @Test("너무 긴 ordered marker를 삽입하면 문단 텍스트를 보존한다")
    func givenTooLongOrderedMarker_whenInsertTextRuns_thenTextIsPreserved() throws {
        // Given
        let blockID: BlockID = "ordered-too-long"
        let insertedText = "1234567890. "
        let editor = EditorModel(
            document: .singleParagraph("", id: blockID),
            selection: .caret(blockID: blockID, offset: 0)
        )
        let expectedKind = BlockKind.paragraph
        let expectedText = insertedText

        // When
        _ = editor.apply(.insertText(insertedText))

        // Then
        let block = try #require(editor.document.blocks[blockID])
        #expect(block.kind == expectedKind)
        #expect(block.content.text == expectedText)
    }

    @Test("숫자가 아닌 ordered marker를 삽입하면 문단 텍스트를 보존한다")
    func givenNonNumericOrderedMarker_whenInsertTextRuns_thenTextIsPreserved() throws {
        // Given
        let blockID: BlockID = "ordered-nonnumeric"
        let insertedText = "a. "
        let editor = EditorModel(
            document: .singleParagraph("", id: blockID),
            selection: .caret(blockID: blockID, offset: 0)
        )
        let expectedKind = BlockKind.paragraph
        let expectedText = insertedText

        // When
        _ = editor.apply(.insertText(insertedText))

        // Then
        let block = try #require(editor.document.blocks[blockID])
        #expect(block.kind == expectedKind)
        #expect(block.content.text == expectedText)
    }

    @Test("음수 ordered marker를 삽입하면 문단 텍스트를 보존한다")
    func givenNegativeOrderedMarker_whenInsertTextRuns_thenTextIsPreserved() throws {
        // Given
        let blockID: BlockID = "ordered-negative"
        let insertedText = "-1. "
        let editor = EditorModel(
            document: .singleParagraph("", id: blockID),
            selection: .caret(blockID: blockID, offset: 0)
        )
        let expectedKind = BlockKind.paragraph
        let expectedText = insertedText

        // When
        _ = editor.apply(.insertText(insertedText))

        // Then
        let block = try #require(editor.document.blocks[blockID])
        #expect(block.kind == expectedKind)
        #expect(block.content.text == expectedText)
    }

    @Test("코드 블록에서는 block markdown marker를 삽입해도 shortcut이 비활성화된다")
    func givenCodeBlock_whenInsertTextRuns_thenShortcutIsDisabled() throws {
        // Given
        let blockID: BlockID = "code"
        let insertedText = "# "
        var document = Document.singleParagraph("", id: blockID)
        try document.setBlockKind(blockID: blockID, kind: .codeBlock(language: nil)).get()
        let editor = EditorModel(
            document: document, selection: .caret(blockID: blockID, offset: 0))
        let expectedKind = BlockKind.codeBlock(language: nil)
        let expectedText = insertedText

        // When
        _ = editor.apply(.insertText(insertedText))

        // Then
        let block = try #require(editor.document.blocks[blockID])
        #expect(block.kind == expectedKind)
        #expect(block.content.text == expectedText)
    }
}
