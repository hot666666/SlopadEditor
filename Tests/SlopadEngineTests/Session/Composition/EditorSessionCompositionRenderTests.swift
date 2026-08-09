import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 조합 렌더링")
struct EditorSessionCompositionRenderTests {
    @Test("조합 입력 렌더링은 원본 문서를 바꾸지 않고 합성 내용을 보여준다")
    func rendersCompositionContent() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hi", id: blockID),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 2)
        )
        // When
        let update = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: blockID,
                    replacementRange: TextRange.point(2),
                    text: "!"
                )
            )
        )
        let composition = try #require(update.composition)
        let snapshot = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 400))
        let blockView = try #require(snapshot.visibleBlocks.first)

        // Then
        #expect(update.invalidation.blockIDs == Set([blockID]))
        #expect(update.invalidation.layoutGeometryChanged)
        #expect(composition.blockID == blockID)
        #expect(composition.replacementRange == TextRange.point(2))
        #expect(composition.text == "!")
        #expect(composition.compositionRevision == 1)
        #expect(update.composition == composition)
        #expect(snapshot.composition == composition)
        #expect(blockView.textRender.measureRequest.text == "Hi!")
        #expect(session.document.block(blockID)?.content.text == "Hi")
        #expect(snapshot.revision.compositionRevision == 1)
    }

    @Test("조합 입력 확정은 문서 변경과 입력 해제 무효화를 하나의 갱신으로 반환한다")
    func commitsComposition() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hlo", id: blockID),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 2)
        )
        _ = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: blockID,
                    replacementRange: TextRange.point(1),
                    text: "el"
                )
            )
        )

        // When
        let update = try #require(session.handleInput(.commitComposition))
        let snapshot = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 400))
        let blockView = try #require(snapshot.visibleBlocks.first)

        // Then
        #expect(update.history.canUndo)
        #expect(update.composition == nil)
        #expect(update.invalidation.blockIDs == Set([blockID]))
        #expect(update.invalidation.layoutGeometryChanged)
        #expect(session.composition == nil)
        #expect(session.document.block(blockID)?.content.text == "Hello")
        #expect(blockView.textRender.measureRequest.text == "Hello")
        #expect(snapshot.composition == nil)
        #expect(snapshot.revision.compositionRevision == 0)
    }

    @Test("조합 입력 취소는 원본 문서를 유지하고 갱신에서 조합 입력을 제거한다")
    func cancelsComposition() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hi", id: blockID),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 2)
        )
        _ = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: blockID,
                    replacementRange: TextRange.point(2),
                    text: "!"
                )
            )
        )

        // When
        let update = try #require(session.handleInput(.cancelComposition))
        let snapshot = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 400))
        let blockView = try #require(snapshot.visibleBlocks.first)

        // Then
        #expect(!update.history.canUndo)
        #expect(update.composition == nil)
        #expect(update.invalidation.blockIDs == Set([blockID]))
        #expect(update.invalidation.layoutGeometryChanged)
        #expect(session.document.block(blockID)?.content.text == "Hi")
        #expect(blockView.textRender.measureRequest.text == "Hi")
        #expect(snapshot.composition == nil)
    }
}
