import Testing

@testable import SlopadEditorEngine
import SlopadCoreModel

@Suite("에디터 세션 블록 drag 입력 이벤트")
struct EditorSessionBlockDragInputEventTests {
    @Test("선택된 블록 drag/drop은 drop target으로 블록 순서를 이동한다")
    func handlesSelectedBlockDragDropReorder() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let d: BlockID = "d"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 10),
            c: BlockMeasurement(height: 10),
            d: BlockMeasurement(height: 10),
        ]
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "B")),
                Block(id: c, content: BlockContent(text: "C")),
                Block(id: d, content: BlockContent(text: "D")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [b, c])),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let beginUpdate = try #require(
            session.handleInput(
                .pointer(
                    .beginBlockDrag(
                        documentPoint: EditorPoint(x: 0, y: 15),
                        viewport: viewport
                    )
                )
            )
        )
        let updateDrag = try #require(
            session.handleInput(
                .pointer(
                    .updateBlockDrag(
                        documentPoint: EditorPoint(x: 0, y: 38),
                        viewport: viewport
                    )
                )
            )
        )
        let dragBeforeDrop = session.blockDrag
        let dropUpdate = try #require(
            session.handleInput(
                .pointer(
                    .endBlockDrag(
                        documentPoint: EditorPoint(x: 0, y: 38),
                        viewport: viewport
                    )
                )
            )
        )

        // Then
        #expect(!beginUpdate.history.canUndo)
        #expect(!updateDrag.history.canUndo)
        #expect(
            dragBeforeDrop?.dropTarget
                == BlockDropTarget(blockID: d, placement: .after)
        )
        #expect(dragBeforeDrop?.dropIndicator?.y == 39)
        #expect(session.document.rootBlockIDs == [a, d, b, c])
        #expect(dropUpdate.history.canUndo)
        #expect(dropUpdate.invalidation.visibleSequenceChanged)
        #expect(dropUpdate.invalidation.layoutGeometryChanged)
        #expect(session.blockDrag == nil)
        #expect(dropUpdate.selection == .blocks(BlockSelection(blockIDs: [b, c])))
    }
}
