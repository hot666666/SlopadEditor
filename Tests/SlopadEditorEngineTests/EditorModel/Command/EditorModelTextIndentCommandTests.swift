import Testing

import SlopadEditorCoreModel
import SlopadEditorDocumentModel

@Suite("EditorModel 텍스트 들여쓰기 명령")
struct EditorModelTextIndentCommandTests {
    @Test("indentText 명령은 선택 범위가 걸친 각 줄 앞에 네 칸을 삽입한다")
    func givenTextSelection_whenIndentTextRuns_thenTouchedLinesAreIndented() {
        // Given
        let blockID: BlockID = "block"
        let editor = EditorModel(
            document: .singleParagraph("alpha\nbeta", id: blockID),
            selection: .text(TextSelection(
                anchor: TextPosition(blockID: blockID, offset: 0),
                focus: TextPosition(blockID: blockID, offset: 10)
            ))
        )
        let expectedSelection = EditorSelection.text(TextSelection(
            anchor: TextPosition(blockID: blockID, offset: 4),
            focus: TextPosition(blockID: blockID, offset: 18)
        ))

        // When
        _ = editor.apply(.indentText(blockID: blockID, range: TextRange(0, 10)))

        // Then
        #expect(editor.document.blocks[blockID]?.content.text == "    alpha\n    beta")
        #expect(editor.selection == expectedSelection)
    }

    @Test("outdentText 명령은 선택 범위가 걸친 각 줄의 최대 네 칸 들여쓰기를 제거한다")
    func givenIndentedTextSelection_whenOutdentTextRuns_thenTouchedLinesAreOutdented() {
        // Given
        let blockID: BlockID = "block"
        let editor = EditorModel(
            document: .singleParagraph("    alpha\n  beta", id: blockID),
            selection: .text(TextSelection(
                anchor: TextPosition(blockID: blockID, offset: 0),
                focus: TextPosition(blockID: blockID, offset: 16)
            ))
        )
        let expectedSelection = EditorSelection.text(TextSelection(
            anchor: TextPosition(blockID: blockID, offset: 0),
            focus: TextPosition(blockID: blockID, offset: 10)
        ))

        // When
        _ = editor.apply(.outdentText(blockID: blockID, range: TextRange(0, 16)))

        // Then
        #expect(editor.document.blocks[blockID]?.content.text == "alpha\nbeta")
        #expect(editor.selection == expectedSelection)
    }
}
