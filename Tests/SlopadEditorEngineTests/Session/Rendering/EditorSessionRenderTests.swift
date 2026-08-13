@testable import SlopadEditorEngine
import SlopadEditorCoreModel
import Testing

@Suite("에디터 세션 렌더링")
struct EditorSessionRenderTests {
    @Test("뷰 스냅샷은 호스트 렌더링용 텍스트 descriptor를 포함한다")
    func viewSnapshotExposesTextRenderDescriptor() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hello", id: blockID),
            textLayouter: RecordingBlockTextLayouter(
                measurementsByBlockID: [
                    blockID: BlockMeasurement(height: 18),
                ]
            )
        )

        // When
        let snapshot = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 100))
        let rendered = try #require(snapshot.visibleBlocks.first)

        // Then
        #expect(rendered.id == blockID)
        #expect(rendered.textRender.measureRequest.blockID == blockID)
        #expect(rendered.textRender.measureRequest.text == "Hello")
        #expect(rendered.textRender.frame == EditorRect(x: 0, y: 0, width: 240, height: 18))
    }

    @Test("순서 목록 렌더링은 렌더링 블록에 파생 마커를 포함한다")
    func rendersBlockMarkers() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([
            Block(id: a, kind: .orderedListItem(restartNumber: nil)),
            Block(id: b, kind: .orderedListItem(restartNumber: nil)),
            Block(id: c, kind: .orderedListItem(restartNumber: 10)),
        ])
        let session = EditorSession(
            document: document,
            textLayouter: RecordingBlockTextLayouter(
                measurementsByBlockID: [
                    a: BlockMeasurement(height: 10),
                    b: BlockMeasurement(height: 10),
                    c: BlockMeasurement(height: 10),
                ]
            )
        )

        // When
        let snapshot = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 400))

        // Then
        #expect(snapshot.visibleBlocks.map(\.markerKind) == [
            .orderedListItem(number: 1),
            .orderedListItem(number: 2),
            .orderedListItem(number: 10),
        ])
    }
}
