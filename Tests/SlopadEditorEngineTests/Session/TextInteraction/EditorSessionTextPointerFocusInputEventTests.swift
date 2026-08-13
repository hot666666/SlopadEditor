import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 텍스트 포인터 focus 입력 이벤트")
struct EditorSessionTextPointerFocusInputEventTests {
    @Test("본문 포인터 이벤트는 런타임이 문서 좌표를 텍스트 위치로 해석한다")
    func handlesPointerFocusTextEvent() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 14),
        ]
        layouter.textPositionsByBlockID[b] = TextPosition(blockID: b, offset: 2)
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "Body")),
            ]),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let update = try #require(
            session.handleInput(
                .pointer(
                    .focusText(
                        documentPoint: EditorPoint(x: 32, y: 12),
                        viewport: viewport
                    )
                )
            )
        )

        // Then
        #expect(update.selection == .caret(blockID: b, offset: 2))
        #expect(session.activeTextPosition()?.blockID == b)
        #expect(layouter.textPositionRequests.map(\.blockID) == [b])
        #expect(layouter.textPositionRequests.first?.point == EditorPoint(x: 32, y: 2))
    }

    @Test("블록 선택 이후 본문 포인터 이벤트는 활성 텍스트 입력 상태로 전환한다")
    func transitionsFromBlockSelectionToTextInput() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 14),
        ]
        layouter.textPositionsByBlockID[b] = TextPosition(blockID: b, offset: 3)
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "Body")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [a]))
        )
        session.replaceTextBackend(layouter)
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let update = try #require(
            session.handleInput(
                .pointer(
                    .focusText(
                        documentPoint: EditorPoint(x: 20, y: 12),
                        viewport: viewport
                    )
                )
            )
        )

        // Then
        #expect(update.selection == .caret(blockID: b, offset: 3))
        #expect(session.activeTextPosition()?.blockID == b)
        #expect(session.activeTextRange() == TextRange.point(3))
    }
}
