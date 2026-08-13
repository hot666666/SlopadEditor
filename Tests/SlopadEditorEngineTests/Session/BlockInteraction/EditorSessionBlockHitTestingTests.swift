@testable import SlopadEditorEngine
import SlopadEditorCoreModel
import Testing

@Suite("에디터 세션 블록 hit-test")
struct EditorSessionBlockHitTestingTests {
    @Test("블록 hit-test는 문서 위치를 레이아웃된 블록으로 해석한다")
    func hitTestsDocumentPoint() throws {
        // Given
        let blockID: BlockID = "a"
        let secondBlockID: BlockID = "b"
        let document = makeFlatDocument([
            Block(id: blockID, content: BlockContent(text: "A")),
            Block(id: secondBlockID, content: BlockContent(text: "B")),
        ])
        let session = EditorSession(
            document: document,
            textLayouter: RecordingBlockTextLayouter(
                measurementsByBlockID: [
                    blockID: BlockMeasurement(height: 10),
                    secondBlockID: BlockMeasurement(height: 10),
                ]
            )
        )
        let viewport = EditorViewport(width: 240, scrollY: 10, height: 10)
        _ = session.render(in: viewport)

        // When
        let hit = try #require(
            session.hitTest(
                documentPoint: EditorPoint(x: 0, y: viewport.scrollY + 1),
                region: .body,
                viewport: viewport
            )
        )
        let outsideDocumentHit = session.hitTest(
            documentPoint: EditorPoint(x: 0, y: -1),
            region: .body,
            viewport: viewport
        )

        // Then
        #expect(hit.blockID == secondBlockID)
        #expect(hit.region == .body)
        #expect(outsideDocumentHit == nil)
    }
}
