import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 텍스트 편집 입력 이벤트")
struct EditorSessionTextEditingInputEventTests {
    @Test("텍스트 입력 이벤트는 런타임 명령 경로로 문서를 변경한다")
    func handlesInsertTextInputEvent() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("", id: blockID))

        // When
        let update = try #require(session.handleInput(.command(.insertText("Hi"))))

        // Then
        #expect(update.history.canUndo)
        #expect(session.document.block(blockID)?.content.text == "Hi")
        #expect(session.activeTextPosition()?.blockID == blockID)
        #expect(session.activeTextRange() == TextRange.point(2))
    }

    @Test("텍스트 replacement 입력 이벤트는 선택 범위를 교체한다")
    func handlesReplaceTextInputEvent() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("Hello", id: blockID))

        // When
        let update = try #require(
            session.handleInput(
                .command(.replaceText(blockID: blockID, range: TextRange(1, 4), text: "i"))
            )
        )

        // Then
        #expect(update.history.canUndo)
        #expect(session.document.block(blockID)?.content.text == "Hio")
        #expect(session.activeTextRange() == TextRange.point(2))
    }

    @Test("텍스트 replacement 입력 이벤트는 빈 문자열로 범위를 삭제한다")
    func handlesDeleteReplacementInputEvent() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("Hello", id: blockID))

        // When
        let update = try #require(
            session.handleInput(
                .command(.replaceText(blockID: blockID, range: TextRange(1, 4), text: ""))
            )
        )

        // Then
        #expect(update.history.canUndo)
        #expect(session.document.block(blockID)?.content.text == "Ho")
        #expect(session.activeTextRange() == TextRange.point(1))
    }
}
