import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 텍스트 이동 입력 이벤트")
struct EditorSessionTextMovementInputEventTests {
    @Test("텍스트 편집 중 Shift-상하는 현재 블록 선택으로 전환한 뒤 기존 블록 선택 동작을 따른다")
    func shiftVerticalArrowsEnterBlockSelectionFromTextEditing() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let session = EditorSession(
            document: makeFlatDocument([Block(id: a), Block(id: b), Block(id: c)]),
            selection: .caret(blockID: b, offset: 0)
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let firstUpdate = try #require(
            session.handleInput(.command(.navigate(.extendDown(viewport: viewport)))))
        let secondUpdate = try #require(
            session.handleInput(.command(.navigate(.extendDown(viewport: viewport)))))

        // Then
        #expect(firstUpdate.selection == .blocks(BlockSelection(blockIDs: [b])))
        let secondSelection = try #require(sessionBlockSelection(secondUpdate.selection))
        #expect(secondSelection.blockIDs == [b, c])
        #expect(secondSelection.anchor == b)
        #expect(secondSelection.focus == c)
    }

    @Test("좌우 이동 입력 명령은 블록 내부와 블록 경계 이동을 런타임에서 처리한다")
    func handlesHorizontalMovementCommandEvents() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "BC")),
            ]),
            selection: .caret(blockID: a, offset: 1)
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let boundaryUpdate = try #require(
            session.handleInput(.command(.navigate(.moveRight(viewport: viewport))))
        )
        let innerUpdate = try #require(
            session.handleInput(.command(.navigate(.moveRight(viewport: viewport))))
        )

        // Then
        #expect(boundaryUpdate.selection == .caret(blockID: b, offset: 0))
        #expect(innerUpdate.selection == .caret(blockID: b, offset: 1))
        #expect(session.activeTextPosition()?.blockID == b)
        #expect(session.activeTextRange() == TextRange.point(1))
    }

    @Test("상하 이동 입력 명령은 같은 블록의 visual line 내부 이동을 먼저 처리한다")
    func handlesVerticalMovementWithinWrappedBlock() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [blockID: BlockMeasurement(height: 24)]
        layouter.lineFragmentsByBlockID[blockID] = [
            LineFragmentSnapshot(
                blockID: blockID,
                range: TextRange(0, 5),
                rect: EditorRect(x: 0, y: 0, width: 50, height: 10)
            ),
            LineFragmentSnapshot(
                blockID: blockID,
                range: TextRange(5, 10),
                rect: EditorRect(x: 0, y: 10, width: 50, height: 10)
            ),
        ]
        layouter.caretRectsByPosition[TextPosition(blockID: blockID, offset: 2)] =
            EditorRect(x: 20, y: 0, width: 1, height: 10)
        layouter.caretRectsByPosition[TextPosition(blockID: blockID, offset: 7)] =
            EditorRect(x: 20, y: 10, width: 1, height: 10)
        layouter.textPositionResolver = { blockID, point in
            TextPosition(blockID: blockID, offset: point.y >= 10 ? 7 : 2)
        }
        let session = EditorSession(
            document: .singleParagraph("abcdefghij", id: blockID),
            selection: .caret(blockID: blockID, offset: 2),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let downUpdate = try #require(session.handleInput(.command(.navigate(.moveDown(viewport: viewport)))))
        let upUpdate = try #require(session.handleInput(.command(.navigate(.moveUp(viewport: viewport)))))

        // Then
        #expect(downUpdate.selection == .caret(blockID: blockID, offset: 7))
        #expect(upUpdate.selection == .caret(blockID: blockID, offset: 2))
    }
}
