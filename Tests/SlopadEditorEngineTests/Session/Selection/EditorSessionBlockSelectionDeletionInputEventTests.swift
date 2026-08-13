import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 블록 선택 삭제 입력 이벤트")
struct EditorSessionBlockSelectionDeletionInputEventTests {
    @Test("블록 선택 삭제는 부분 선택을 삭제하고 selection을 inactive로 전환한다")
    func deletesPartialBlockSelectionToInactive() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let session = EditorSession(
            document: makeFlatDocument([Block(id: a), Block(id: b), Block(id: c)]),
            selection: .blocks(BlockSelection(blockIDs: [b]))
        )

        // When
        let update = try #require(session.handleInput(.command(.deleteBackward)))

        // Then
        #expect(session.document.rootBlockIDs == [a, c])
        #expect(session.document.block(b) == nil)
        #expect(update.selection == .inactive)
    }

    @Test("모든 visible block 선택 삭제는 빈 문단 하나로 reset하고 caret을 0으로 둔다")
    func deletesFullBlockSelectionToEmptyParagraph() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([Block(id: a), Block(id: b)]),
            selection: .blocks(BlockSelection(blockIDs: [a, b]))
        )

        // When
        let update = try #require(session.handleInput(.command(.deleteForward)))

        // Then
        #expect(session.document.blocks.count == 1)
        let resetID = try #require(session.document.rootBlockIDs.first)
        #expect(resetID == a)
        #expect(session.document.block(resetID)?.content.text == "")
        #expect(update.selection == .caret(blockID: resetID, offset: 0))
    }
}
