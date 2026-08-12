import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 블록 포인터 선택 입력 이벤트")
struct EditorSessionBlockPointerSelectionInputEventTests {
    @Test("블록 포인터 이벤트는 런타임 블록 선택 상태로 해석된다")
    func handlesPointerBlockSelectionEvent() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 14),
        ]
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
                    .selectBlock(
                        documentPoint: EditorPoint(x: 0, y: 12),
                        region: .gutter,
                        viewport: viewport
                    )
                )
            )
        )

        // Then
        let blockSelection = try #require(sessionBlockSelection(update.selection))
        #expect(blockSelection.blockIDs == [b])
        #expect(session.activeTextPosition() == nil)
        #expect(session.activeTextRange() == nil)
    }

    @Test("포인터 drag 블록 선택 이벤트는 런타임이 보관한 anchor부터 현재 hit block까지 선택한다")
    func handlesPointerBlockSelectionDragEvent() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 10),
            c: BlockMeasurement(height: 10),
        ]
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "B")),
                Block(id: c, content: BlockContent(text: "C")),
            ]),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        _ = try #require(
            session.handleInput(
                .pointer(
                    .selectBlock(
                        documentPoint: EditorPoint(x: 0, y: 5),
                        region: .gutter,
                        viewport: viewport
                    )
                )
            )
        )
        let update = try #require(
            session.handleInput(
                .pointer(
                    .extendBlockSelection(
                        documentPoint: EditorPoint(x: 0, y: 25),
                        region: .gutter,
                        viewport: viewport
                    )
                )
            )
        )

        // Then
        let blockSelection = try #require(sessionBlockSelection(update.selection))
        #expect(blockSelection.blockIDs == [a, b, c])
        #expect(blockSelection.anchor == a)
        #expect(blockSelection.focus == c)
    }

    @Test("블록 선택 drag 종료 후에는 런타임이 drag anchor를 사용하지 않는다")
    func endsPointerBlockSelectionDragEvent() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 10),
        ]
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "B")),
            ]),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        _ = try #require(
            session.handleInput(
                .pointer(
                    .selectBlock(
                        documentPoint: EditorPoint(x: 0, y: 5),
                        region: .gutter,
                        viewport: viewport
                    )
                )
            )
        )
        _ = session.handleInput(.pointer(.endBlockSelection))
        let updateAfterEndedDrag = session.handleInput(
            .pointer(
                .extendBlockSelection(
                    documentPoint: EditorPoint(x: 0, y: 15),
                    region: .gutter,
                    viewport: viewport
                )
            )
        )

        // Then
        #expect(updateAfterEndedDrag == nil)
        let snapshot = session.render(in: viewport)
        #expect(snapshot.selection == .blocks(BlockSelection(blockIDs: [a])))
    }
}
