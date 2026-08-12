import Testing

@testable import SlopadEditorEngine
import SlopadCoreModel

@Suite("에디터 세션 update projection")
struct EditorSessionUpdateProjectionTests {
    @Test("명령 transaction은 update와 다음 render snapshot에 반영된다")
    func projectsCommandTransactionIntoUpdateAndRender() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("", id: blockID),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 2)
        )

        // When
        let update = try #require(session.handleInput(.command(.insertText("Hi"))))
        let snapshot: EditorSessionSnapshot = session.render(
            in: EditorViewport(width: 240, scrollY: 0, height: 400))
        let blockView = try #require(snapshot.visibleBlocks.first)

        // Then
        #expect(update.invalidation.blockIDs == Set([blockID]))
        #expect(update.history.canUndo)
        #expect(snapshot.visibleBlocks.count == 1)
        #expect(blockView.id == blockID)
        #expect(blockView.textRender.measureRequest.text == "Hi")
        #expect(blockView.depth == 0)
        #expect(blockView.frame == EditorRect(x: 0, y: 0, width: 240, height: 12))
        #expect(snapshot.totalHeight == 12)
        #expect(snapshot.history.canUndo)
    }

    @Test("입력 명령의 구조 변경은 Session에서 host invalidation으로 투영된다")
    func projectsStructuralInputIntoLayoutAndUpdateInvalidations() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("", id: blockID),
            selection: .caret(blockID: blockID, offset: 0),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 2)
        )

        // When
        let update = try #require(session.handleInput(.command(.enter)))
        let createdID = try #require(sessionCaretPosition(update.selection)?.blockID)

        // Then
        #expect(update.invalidation.blockIDs == Set([blockID, createdID]))
        #expect(update.invalidation.visibleSequenceChanged)
        #expect(update.invalidation.layoutGeometryChanged)
    }
}
