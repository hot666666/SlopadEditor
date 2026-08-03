import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 시각 줄 네비게이션")
struct EditorSessionVisualLineNavigationTests {
    @Test("시각 줄 경계 이동은 세션이 텍스트 geometry를 사용해 다음 블록 위치를 선택한다")
    func movesAcrossVisualLineBoundary() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let geometry = SpyBlockTextLayouter()
        geometry.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 10),
        ]
        geometry.lineFragmentsByBlockID[a] = [
            LineFragmentSnapshot(
                blockID: a,
                range: TextRange(0, 4),
                rect: EditorRect(x: 0, y: 0, width: 80, height: 10)
            )
        ]
        geometry.lineFragmentsByBlockID[b] = [
            LineFragmentSnapshot(
                blockID: b,
                range: TextRange(0, 10),
                rect: EditorRect(x: 0, y: 0, width: 100, height: 10)
            )
        ]
        geometry.caretRectsByPosition[TextPosition(blockID: a, offset: 4)] =
            EditorRect(x: 80, y: 0, width: 1, height: 10)
        geometry.textPositionsByBlockID[b] = TextPosition(blockID: b, offset: 8)
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "Line")),
                Block(id: b, content: BlockContent(text: "Next block")),
            ]),
            selection: .caret(blockID: a, offset: 4),
            textLayouter: geometry
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let update = try #require(
            session.moveAcrossVisualLineBoundaryIfNeeded(
                direction: EditorNavigationDirection.down,
                viewport: viewport
            )
        )

        // Then
        #expect(update.selection == EditorSelection.caret(blockID: b, offset: 8))
        #expect(geometry.textPositionRequests.map(\.blockID) == [b])
    }

    @Test("시각 줄 경계 위치는 실제 caret rect가 있는 줄에서 다음 줄로 이동한다")
    func lineBoundaryMovementUsesCaretVisualLine() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let geometry = SpyBlockTextLayouter()
        geometry.measurementsByBlockID = [
            a: BlockMeasurement(height: 20),
            b: BlockMeasurement(height: 10),
        ]
        geometry.lineFragmentsByBlockID[a] = [
            LineFragmentSnapshot(
                blockID: a,
                range: TextRange(0, 4),
                rect: EditorRect(x: 0, y: 0, width: 80, height: 10)
            ),
            LineFragmentSnapshot(
                blockID: a,
                range: TextRange(4, 8),
                rect: EditorRect(x: 0, y: 10, width: 80, height: 10)
            ),
        ]
        geometry.lineFragmentsByBlockID[b] = [
            LineFragmentSnapshot(
                blockID: b,
                range: TextRange(0, 10),
                rect: EditorRect(x: 0, y: 0, width: 100, height: 10)
            )
        ]
        geometry.caretRectsByPosition[TextPosition(blockID: a, offset: 4)] =
            EditorRect(x: 50, y: 10, width: 1, height: 10)
        geometry.textPositionsByBlockID[b] = TextPosition(blockID: b, offset: 5)
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "LineNext")),
                Block(id: b, content: BlockContent(text: "Next block")),
            ]),
            selection: .caret(blockID: a, offset: 4),
            textLayouter: geometry
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let update = try #require(
            session.moveAcrossVisualLineBoundaryIfNeeded(
                direction: EditorNavigationDirection.down,
                viewport: viewport
            )
        )

        // Then
        #expect(update.selection == EditorSelection.caret(blockID: b, offset: 5))
        #expect(geometry.textPositionRequests.map(\.blockID) == [b])
    }

    @Test("다음 블록 hit-test가 실패하면 시각 줄 경계 이동을 적용하지 않는다")
    func ignoresVisualLineMovementWhenHitTestFails() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let geometry = SpyBlockTextLayouter()
        geometry.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 10),
        ]
        geometry.lineFragmentsByBlockID[a] = [
            LineFragmentSnapshot(
                blockID: a,
                range: TextRange(0, 4),
                rect: EditorRect(x: 0, y: 0, width: 80, height: 10)
            )
        ]
        geometry.lineFragmentsByBlockID[b] = [
            LineFragmentSnapshot(
                blockID: b,
                range: TextRange(0, 10),
                rect: EditorRect(x: 0, y: 0, width: 100, height: 10)
            )
        ]
        geometry.caretRectsByPosition[TextPosition(blockID: a, offset: 4)] =
            EditorRect(x: 80, y: 0, width: 1, height: 10)
        geometry.textHitTestResolver = { _, _ in nil }
        let originalSelection = EditorSelection.caret(blockID: a, offset: 4)
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "Line")),
                Block(id: b, content: BlockContent(text: "Next block")),
            ]),
            selection: originalSelection,
            textLayouter: geometry
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let update = session.moveAcrossVisualLineBoundaryIfNeeded(
            direction: EditorNavigationDirection.down,
            viewport: viewport
        )

        // Then
        #expect(update == nil)
        #expect(session.editorModel.selection == originalSelection)
        #expect(geometry.textPositionRequests.map(\.blockID) == [b])
    }

    @Test("다음 블록 hit-test 결과가 잘못된 위치면 시각 줄 경계 이동을 적용하지 않는다")
    func ignoresInvalidVisualLineHitPosition() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let geometry = SpyBlockTextLayouter()
        geometry.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 10),
        ]
        geometry.lineFragmentsByBlockID[a] = [
            LineFragmentSnapshot(
                blockID: a,
                range: TextRange(0, 4),
                rect: EditorRect(x: 0, y: 0, width: 80, height: 10)
            )
        ]
        geometry.lineFragmentsByBlockID[b] = [
            LineFragmentSnapshot(
                blockID: b,
                range: TextRange(0, 10),
                rect: EditorRect(x: 0, y: 0, width: 100, height: 10)
            )
        ]
        geometry.caretRectsByPosition[TextPosition(blockID: a, offset: 4)] =
            EditorRect(x: 80, y: 0, width: 1, height: 10)
        geometry.textPositionsByBlockID[b] = TextPosition(blockID: "other", offset: 3)
        let originalSelection = EditorSelection.caret(blockID: a, offset: 4)
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "Line")),
                Block(id: b, content: BlockContent(text: "Next block")),
            ]),
            selection: originalSelection,
            textLayouter: geometry
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let update = session.moveAcrossVisualLineBoundaryIfNeeded(
            direction: EditorNavigationDirection.down,
            viewport: viewport
        )

        // Then
        #expect(update == nil)
        #expect(session.editorModel.selection == originalSelection)
    }
}
