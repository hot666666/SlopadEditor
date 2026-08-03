import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 텍스트 hit-test")
struct EditorSessionTextHitTestingTests {
    @Test("본문 클릭 위치는 세션이 블록 내부 텍스트 위치로 해석한다")
    func focusesTextAtDocumentPoint() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let geometry = SpyBlockTextLayouter()
        geometry.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 14),
        ]
        geometry.textPositionsByBlockID[b] = TextPosition(blockID: b, offset: 2)
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "Body")),
            ]),
            textLayouter: geometry
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let update = try #require(
            session.focusText(at: EditorPoint(x: 48, y: 12), viewport: viewport)
        )

        // Then
        #expect(update.selection == EditorSelection.caret(blockID: b, offset: 2))
        #expect(geometry.textPositionRequests.map(\.blockID) == [b])
        #expect(geometry.textPositionRequests.first?.point == EditorPoint(x: 48, y: 2))
    }

    @Test("backend hit-test가 다른 블록 위치를 반환하면 선택을 변경하지 않는다")
    func rejectsHitPositionForAnotherBlock() {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID[blockID] = BlockMeasurement(height: 10)
        layouter.textPositionsByBlockID[blockID] = TextPosition(blockID: "other", offset: 1)
        let session = EditorSession(
            document: .singleParagraph("Body", id: blockID),
            selection: .caret(blockID: blockID, offset: 2),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let update = session.focusText(
            at: EditorPoint(x: 20, y: 5),
            viewport: viewport
        )

        // Then
        #expect(update == nil)
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 2))
    }

    @Test("backend hit-test가 유효 텍스트 범위 밖 offset을 반환하면 위치를 노출하지 않는다")
    func rejectsHitPositionOutsideEffectiveText() {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID[blockID] = BlockMeasurement(height: 10)
        let session = EditorSession(
            document: .singleParagraph("Body", id: blockID),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        layouter.textPositionsByBlockID[blockID] = TextPosition(blockID: blockID, offset: -1)
        let negativePosition = session.textPosition(
            at: EditorPoint(x: 20, y: 5),
            viewport: viewport
        )
        layouter.textPositionsByBlockID[blockID] = TextPosition(blockID: blockID, offset: 5)
        let overflowingPosition = session.textPosition(
            in: blockID,
            at: EditorPoint(x: 20, y: 5),
            viewport: viewport
        )

        // Then
        #expect(negativePosition == nil)
        #expect(overflowingPosition == nil)
    }

    @Test("backend가 hit-test 변환에 실패하면 offset 0으로 대체하지 않는다")
    func preservesSelectionWhenHitTestFails() {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID[blockID] = BlockMeasurement(height: 10)
        layouter.textHitTestResolver = { _, _ in nil }
        let originalSelection = EditorSelection.caret(blockID: blockID, offset: 2)
        let session = EditorSession(
            document: .singleParagraph("Body", id: blockID),
            selection: originalSelection,
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let update = session.focusText(
            at: EditorPoint(x: 20, y: 5),
            viewport: viewport
        )

        // Then
        #expect(update == nil)
        #expect(session.editorModel.selection == originalSelection)
        #expect(layouter.textPositionRequests.map(\.blockID) == [blockID])
    }

    @Test("조합 중 같은 블록 hit-test는 canonical 선택 대신 유효 선택만 이동한다")
    func focusesEffectiveCompositionText() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID[blockID] = BlockMeasurement(height: 10)
        layouter.textHitTestResolver = { _, _ in
            TextHitTestResult(
                position: TextPosition(blockID: blockID, offset: 3),
                navigationContext: TextNavigationContext(preferredInlineOffset: 33)
            )
        }
        let session = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.handleInput(
            .beginComposition(
                blockID: blockID,
                replacementRange: TextRange.point(1),
                text: "XYZ"
            )
        )

        // When
        let update = try #require(
            session.focusText(at: EditorPoint(x: 20, y: 5), viewport: viewport)
        )

        // Then
        #expect(update.selection == .caret(blockID: blockID, offset: 3))
        #expect(session.activeTextRange() == TextRange.point(3))
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 1))
        #expect(session.composition != nil)
        #expect(session.textNavigationRuntimeContext?.backendContext.preferredInlineOffset == 33)
    }
}
