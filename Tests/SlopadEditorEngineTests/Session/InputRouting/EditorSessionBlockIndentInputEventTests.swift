import Testing

@testable import SlopadEditorEngine
import SlopadCoreModel

@Suite("에디터 세션 블록 들여쓰기 입력 이벤트")
struct EditorSessionBlockIndentInputEventTests {
    @Test("블록 선택의 Indent 입력 명령은 선택 블록을 구조적으로 들여쓴다")
    func indentsSelectedBlocksInBlockSelectionMode() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "Parent")),
                Block(id: b, content: BlockContent(text: "Body")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [b]))
        )

        // When
        let update = try #require(session.handleInput(.command(.indent)))

        // Then
        #expect(session.document.blocks[b]?.parentID == a)
        #expect(update.selection == .blocks(BlockSelection(blockIDs: [b])))
        #expect(update.invalidation.visibleSequenceChanged)
        #expect(update.invalidation.layoutGeometryChanged)
    }
}
