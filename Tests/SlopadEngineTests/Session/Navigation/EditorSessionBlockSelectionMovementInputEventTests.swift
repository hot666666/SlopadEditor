import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 블록 선택 이동 입력 이벤트")
struct EditorSessionBlockSelectionMovementInputEventTests {
    @Test("블록 선택 상하 이동은 선택 range 크기를 유지하며 visible order에서 한 칸 이동한다")
    func movesBlockSelectionRangeVertically() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let d: BlockID = "d"
        let session = EditorSession(
            document: makeFlatDocument([Block(id: a), Block(id: b), Block(id: c), Block(id: d)]),
            selection: .blocks(BlockSelection(blockIDs: [b, c], anchor: b, focus: c))
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let upUpdate = try #require(session.handleInput(.command(.navigate(.moveUp(viewport: viewport)))))
        let downUpdate = try #require(session.handleInput(.command(.navigate(.moveDown(viewport: viewport)))))

        // Then
        #expect(sessionBlockSelection(upUpdate.selection)?.blockIDs == [a, b])
        #expect(sessionBlockSelection(downUpdate.selection)?.blockIDs == [b, c])
    }

    @Test("블록 선택 Shift-상하는 anchor를 유지하고 focus 이동으로 range를 확장하거나 축소한다")
    func extendsBlockSelectionWithShiftArrows() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let session = EditorSession(
            document: makeFlatDocument([Block(id: a), Block(id: b), Block(id: c)]),
            selection: .blocks(BlockSelection(blockIDs: [b], anchor: b, focus: b))
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let downUpdate = try #require(
            session.handleInput(.command(.navigate(.extendDown(viewport: viewport)))))
        let upUpdate = try #require(session.handleInput(.command(.navigate(.extendUp(viewport: viewport)))))

        // Then
        let extended = try #require(sessionBlockSelection(downUpdate.selection))
        #expect(extended.blockIDs == [b, c])
        #expect(extended.anchor == b)
        #expect(extended.focus == c)
        let shrunk = try #require(sessionBlockSelection(upUpdate.selection))
        #expect(shrunk.blockIDs == [b])
        #expect(shrunk.anchor == b)
        #expect(shrunk.focus == b)
    }

    @Test("블록 선택의 좌우 방향키는 현재 scope에서 no-op이다")
    func ignoresHorizontalArrowsWhenBlockSelected() {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .blocks(BlockSelection(blockIDs: [blockID]))
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let left = session.handleInput(.command(.navigate(.moveLeft(viewport: viewport))))
        let right = session.handleInput(.command(.navigate(.moveRight(viewport: viewport))))

        // Then
        #expect(left == nil)
        #expect(right == nil)
        #expect(session.render(in: viewport).selection == .blocks(BlockSelection(blockIDs: [blockID])))
    }
}
