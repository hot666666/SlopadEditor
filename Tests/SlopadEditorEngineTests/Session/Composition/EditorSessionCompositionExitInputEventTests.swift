import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 조합 종료 입력 이벤트")
struct EditorSessionCompositionExitInputEventTests {
    @Test("조합 중 다른 블록 선택으로 전환하면 조합을 commit한 뒤 블록 선택으로 전환한다")
    func commitsCompositionWhenSelectingBlock() throws {
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
            selection: .caret(blockID: a, offset: 1),
            textLayouter: layouter
        )
        _ = session.handleInput(
            .beginComposition(
                blockID: a,
                replacementRange: TextRange.point(1),
                text: "!"
            )
        )

        // When
        let update = try #require(
            session.handleInput(
                .pointer(
                    .selectBlock(
                        documentPoint: EditorPoint(x: 0, y: 12),
                        region: .gutter,
                        viewport: EditorViewport(width: 240, scrollY: 0, height: 400)
                    )
                )
            )
        )

        // Then
        let blockSelection = try #require(sessionBlockSelection(update.selection))
        #expect(blockSelection.blockIDs == [b])
        #expect(update.history.canUndo)
        #expect(update.composition == nil)
        #expect(session.composition == nil)
        #expect(session.document.block(a)?.content.text == "A!")
        #expect(update.invalidation.blockIDs == Set([a]))
        #expect(update.invalidation.layoutGeometryChanged)
    }

    @Test("조합 중 다른 블록 텍스트 포커스로 전환하면 조합을 commit한 뒤 포커스를 이동한다")
    func commitsCompositionWhenFocusingDifferentBlock() throws {
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
            selection: .caret(blockID: a, offset: 1),
            textLayouter: layouter
        )
        _ = session.handleInput(
            .beginComposition(
                blockID: a,
                replacementRange: TextRange.point(1),
                text: "!"
            )
        )

        // When
        let update = try #require(
            session.handleInput(
                .pointer(
                    .focusText(
                        documentPoint: EditorPoint(x: 24, y: 12),
                        viewport: EditorViewport(width: 240, scrollY: 0, height: 400)
                    )
                )
            )
        )

        // Then
        #expect(update.selection == .caret(blockID: b, offset: 2))
        #expect(update.history.canUndo)
        #expect(update.composition == nil)
        #expect(session.composition == nil)
        #expect(session.document.block(a)?.content.text == "A!")
        #expect(update.invalidation.blockIDs == Set([a]))
        #expect(session.activeTextPosition()?.blockID == b)
        #expect(session.activeTextRange() == TextRange.point(2))
    }

    @Test("조합 중 empty area click은 조합을 commit한 뒤 inactive로 전환한다")
    func commitsCompositionBeforeEmptyAreaClick() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [blockID: BlockMeasurement(height: 10)]
        let session = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: layouter
        )
        _ = session.handleInput(
            .beginComposition(
                blockID: blockID,
                replacementRange: TextRange.point(1),
                text: "!"
            )
        )

        // When
        let update = try #require(
            session.handleInput(
                .pointer(
                    .focusText(
                        documentPoint: EditorPoint(x: 20, y: 200),
                        viewport: EditorViewport(width: 240, scrollY: 0, height: 400)
                    )
                )
            )
        )

        // Then
        #expect(update.history.canUndo)
        #expect(update.selection == .inactive)
        #expect(session.document.block(blockID)?.content.text == "A!")
        #expect(session.composition == nil)
    }
}
