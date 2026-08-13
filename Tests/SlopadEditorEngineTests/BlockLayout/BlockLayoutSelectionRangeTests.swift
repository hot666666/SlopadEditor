import Testing

@testable import SlopadEditorBlockLayout
import SlopadEditorCoreModel

@Suite("BlockLayout selection range 조회")
struct BlockLayoutSelectionRangeTests {
    @Test("블록 ID 범위는 BlockLayout visible 순서로 연속 블록 선택이 된다")
    func blockIDRangeResolvesAgainstBlockLayoutVisibleOrder() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([Block(id: a), Block(id: b), Block(id: c)])
        let blockLayout = BlockLayout()

        // When
        let selection = try #require(
            blockLayout.blockSelection(
                from: b,
                to: c,
                document: document
            )
        )

        // Then
        #expect(selection.blockIDs == [b, c])
        #expect(selection.anchor == b)
        #expect(selection.focus == c)
    }

    @Test("BlockLayout visible 순서 밖 block ID는 블록 선택을 만들지 않는다")
    func blockIDOutsideBlockLayoutVisibleOrderReturnsNil() {
        // Given
        let document = makeFlatDocument([Block(id: "a"), Block(id: "b")])
        let blockLayout = BlockLayout()

        // When
        let selection = blockLayout.blockSelection(
            from: "a",
            to: "missing",
            document: document
        )

        // Then
        #expect(selection == nil)
    }

    @Test("블록 선택 이동은 visible order 안에서 선택 폭과 anchor/focus 상대 위치를 유지한다")
    func movedBlockSelectionPreservesSelectionShapeInVisibleOrder() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let d: BlockID = "d"
        let document = makeFlatDocument([Block(id: a), Block(id: b), Block(id: c), Block(id: d)])
        let blockLayout = BlockLayout()
        let selection = BlockSelection(blockIDs: [b, c], anchor: c, focus: b)

        // When
        let moved = try #require(
            blockLayout.movedBlockSelection(
                selection,
                by: 1,
                document: document
            )
        )

        // Then
        #expect(moved.blockIDs == [c, d])
        #expect(moved.anchor == d)
        #expect(moved.focus == c)
    }

    @Test("블록 선택 이동이 visible order 밖으로 나가면 nil을 반환한다")
    func movedBlockSelectionRejectsOutOfBoundsMove() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let document = makeFlatDocument([Block(id: a), Block(id: b)])
        let blockLayout = BlockLayout()
        let selection = BlockSelection(blockIDs: [a], anchor: a, focus: a)

        // When
        let moved = blockLayout.movedBlockSelection(selection, by: -1, document: document)

        // Then
        #expect(moved == nil)
    }

    @Test("블록 선택 확장은 anchor를 유지하고 focus를 visible order 안에서 이동한다")
    func extendedBlockSelectionKeepsAnchorAndMovesFocusInVisibleOrder() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([Block(id: a), Block(id: b), Block(id: c)])
        let blockLayout = BlockLayout()
        let selection = BlockSelection(blockIDs: [b], anchor: b, focus: b)

        // When
        let extended = try #require(
            blockLayout.extendedBlockSelection(selection, by: 1, document: document)
        )

        // Then
        #expect(extended.blockIDs == [b, c])
        #expect(extended.anchor == b)
        #expect(extended.focus == c)
    }
}
