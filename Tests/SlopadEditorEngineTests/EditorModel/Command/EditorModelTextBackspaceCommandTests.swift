import Testing

import SlopadEditorCoreModel
import SlopadEditorDocumentModel

@Suite("EditorModel text Backspace 키 명령")
struct EditorModelTextBackspaceCommandTests {
    @Test("캐럿이 블록 중간에 있으면 Backspace 키 명령은 이전 글자를 삭제한다")
    func givenCaretAfterCharacter_whenBackspace_thenPreviousCharacterIsDeleted() {
        // Given
        let blockID: BlockID = "block"
        let editor = EditorModel(
            document: .singleParagraph("ABC", id: blockID),
            selection: .caret(blockID: blockID, offset: 2)
        )
        let expectedText = "AC"
        let expectedSelection = EditorSelection.caret(blockID: blockID, offset: 1)

        // When
        _ = editor.apply(.handleBackspace)

        // Then
        #expect(editor.document.blocks[blockID]?.content.text == expectedText)
        #expect(editor.selection == expectedSelection)
    }

    @Test("단일 블록 텍스트 선택에서 Backspace 키 명령은 선택 범위를 삭제한다")
    func givenTextSelection_whenBackspace_thenSelectedRangeIsDeleted() {
        // Given
        let blockID: BlockID = "block"
        let editor = EditorModel(
            document: .singleParagraph("HelloWorld", id: blockID),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 5),
                    focus: TextPosition(blockID: blockID, offset: 10)
                ))
        )
        let expectedText = "Hello"
        let expectedSelection = EditorSelection.caret(blockID: blockID, offset: 5)

        // When
        _ = editor.apply(.handleBackspace)

        // Then
        #expect(editor.document.blocks[blockID]?.content.text == expectedText)
        #expect(editor.selection == expectedSelection)
    }
}
