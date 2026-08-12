import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 Backspace 입력 이벤트")
struct EditorSessionBackspaceInputEventTests {
    @Test("Backspace 입력 명령은 블록 시작에서 이전 블록으로 병합하고 활성 입력 상태를 반환한다")
    func handlesBackspaceMergeBoundaryCommand() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "Hello")),
                Block(id: b, content: BlockContent(text: "World")),
            ]),
            selection: .caret(blockID: b, offset: 0)
        )

        // When
        let update = try #require(session.handleInput(.command(.deleteBackward)))

        // Then
        #expect(update.history.canUndo)
        #expect(session.document.rootBlockIDs == [a])
        #expect(session.document.block(a)?.content.text == "HelloWorld")
        #expect(session.document.block(b) == nil)
        #expect(update.selection == .caret(blockID: a, offset: 5))
        #expect(update.invalidation.visibleSequenceChanged)
        #expect(update.invalidation.layoutGeometryChanged)
    }
}
