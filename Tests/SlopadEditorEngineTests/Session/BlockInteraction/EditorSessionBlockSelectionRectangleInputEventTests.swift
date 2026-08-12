import Testing

@testable import SlopadEditorEngine
import SlopadCoreModel

@Suite("에디터 세션 블록 사각 선택 입력 이벤트")
struct EditorSessionBlockSelectionRectangleInputEventTests {
    @Test("사각 선택 drag는 영역과 겹치는 블록을 선택하고 snapshot에 표시 영역을 노출한다")
    func selectsBlocksIntersectingRectangle() throws {
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
            selection: .caret(blockID: b, offset: 0),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let beginUpdate = try #require(
            session.handleInput(
                .pointer(
                    .beginBlockSelectionRectangle(
                        documentPoint: EditorPoint(x: 200, y: 20),
                        viewport: viewport
                    )
                )
            )
        )
        let dragUpdate = try #require(
            session.handleInput(
                .pointer(
                    .updateBlockSelectionRectangle(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    )
                )
            )
        )
        let snapshot = session.render(in: viewport)

        // Then
        #expect(beginUpdate.selection == .inactive)
        #expect(
            dragUpdate.selection
                == .blocks(BlockSelection(blockIDs: [a, b], anchor: a, focus: b))
        )
        #expect(
            snapshot.blockSelectionRectangleState?.rect
                == EditorRect(x: 20, y: 5, width: 180, height: 15)
        )
        #expect(snapshot.selection == dragUpdate.selection)
        #expect(session.activeTextPosition() == nil)
    }

    @Test("사각 선택 drag 종료 후에는 표시 영역만 지우고 블록 선택은 유지한다")
    func endsRectangleSelectionWithoutClearingBlockSelection() throws {
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
                    .beginBlockSelectionRectangle(
                        documentPoint: EditorPoint(x: 200, y: 20),
                        viewport: viewport
                    )
                )
            )
        )
        _ = try #require(
            session.handleInput(
                .pointer(
                    .updateBlockSelectionRectangle(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    )
                )
            )
        )
        let endUpdate = try #require(
            session.handleInput(.pointer(.endBlockSelectionRectangle))
        )
        let updateAfterEndedDrag = session.handleInput(
            .pointer(
                .updateBlockSelectionRectangle(
                    documentPoint: EditorPoint(x: 20, y: 15),
                    viewport: viewport
                )
            )
        )
        let snapshot = session.render(in: viewport)

        // Then
        #expect(endUpdate.selection == .blocks(BlockSelection(blockIDs: [a, b])))
        #expect(snapshot.blockSelectionRectangleState == nil)
        #expect(snapshot.selection == .blocks(BlockSelection(blockIDs: [a, b])))
        #expect(updateAfterEndedDrag == nil)
    }

    @Test("사각 선택 drag는 autoscroll 후에도 현재 viewport로 선택 범위를 자르지 않는다")
    func selectsBlocksAcrossScrolledViewport() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let d: BlockID = "d"
        let e: BlockID = "e"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 10),
            c: BlockMeasurement(height: 10),
            d: BlockMeasurement(height: 10),
            e: BlockMeasurement(height: 10),
        ]
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "B")),
                Block(id: c, content: BlockContent(text: "C")),
                Block(id: d, content: BlockContent(text: "D")),
                Block(id: e, content: BlockContent(text: "E")),
            ]),
            textLayouter: layouter
        )
        let initialViewport = EditorViewport(width: 240, scrollY: 0, height: 20)
        let scrolledViewport = EditorViewport(width: 240, scrollY: 20, height: 20)

        // When
        _ = try #require(
            session.handleInput(
                .pointer(
                    .beginBlockSelectionRectangle(
                        documentPoint: EditorPoint(x: 200, y: 5),
                        viewport: initialViewport
                    )
                )
            )
        )
        let dragUpdate = try #require(
            session.handleInput(
                .pointer(
                    .updateBlockSelectionRectangle(
                        documentPoint: EditorPoint(x: 20, y: 35),
                        viewport: scrolledViewport
                    )
                )
            )
        )

        // Then
        #expect(
            dragUpdate.selection
                == .blocks(BlockSelection(blockIDs: [a, b, c, d], anchor: a, focus: d))
        )
    }
}
