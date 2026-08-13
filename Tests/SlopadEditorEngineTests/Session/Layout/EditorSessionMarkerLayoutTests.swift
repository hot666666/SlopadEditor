import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 마커 레이아웃")
struct EditorSessionMarkerLayoutTests {
    @Test("visible 순서가 유지되는 block kind 변경도 marker state을 갱신한다")
    func markerUpdatesAfterBlockKindChange() {
        // Given
        let a: BlockID = "a"
        let textLayouter = RecordingBlockTextLayouter()
        let session = EditorSession(
            document: .singleParagraph("task", id: a),
            textLayouter: textLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()

        // When
        _ = session.handleCommand(.setBlockKind(blockID: a, kind: .todo(isChecked: true)))
        let snapshot = session.render(in: viewport)

        // Then
        #expect(snapshot.visibleBlocks.map(\.markerKind) == [.todo(isChecked: true)])
        #expect(textLayouter.measuredBlockIDs == [a])
    }

    @Test("marker가 있는 structural reorder도 marker state을 유지한다")
    func markerUpdatesAfterStructuralMove() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let textLayouter = RecordingBlockTextLayouter()
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, kind: .unorderedListItem, content: BlockContent(text: "B")),
                Block(id: c, content: BlockContent(text: "C")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [b])),
            textLayouter: textLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()

        // When
        _ = session.handleCommand(
            .moveBlockSelection(
                BlockSelection(blockIDs: [b]),
                target: BlockDropTarget(blockID: c, placement: .after)
            )
        )
        let snapshot = session.render(in: viewport)

        // Then
        #expect(snapshot.visibleBlocks.map(\.id) == [a, c, b])
        #expect(snapshot.visibleBlocks.map(\.markerKind) == [.none, .none, .unorderedListItem])
        #expect(textLayouter.measuredBlockIDs.isEmpty)
    }
}
