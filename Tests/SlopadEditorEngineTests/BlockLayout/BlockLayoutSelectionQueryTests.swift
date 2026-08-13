import Testing

@testable import SlopadEditorBlockLayout
import SlopadEditorCoreModel

@Suite("BlockLayout 선택 조회")
struct BlockLayoutSelectionQueryTests {
    @Test("전체 visible block 선택은 visible order 전체를 anchor/focus로 감싼다")
    func allVisibleBlockSelectionUsesVisibleOrder() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        var document = makeFlatDocument([Block(id: a), Block(id: c)])
        document.appendChild(Block(id: b), to: a)
        let blockLayout = BlockLayout()

        // When
        let selection = try #require(blockLayout.allVisibleBlockSelection(document: document))

        // Then
        #expect(selection.blockIDs == [a, b, c])
        #expect(selection.anchor == a)
        #expect(selection.focus == c)
    }

    @Test("y 범위 block selection은 height index에서 겹치는 visible block만 선택한다")
    func yRangeSelectionUsesHeightIndex() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "BB")),
            Block(id: c, content: BlockContent(text: "CCC")),
        ])
        let layoutInput = makeBlockLayoutTestInput(
            document: document,
            availableWidth: 300
        )
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()
        _ = runBlockLayoutPass(&blockLayout, input: layoutInput, textLayouter: textLayouter)

        // When
        let middleOnly = try #require(
            blockLayout.blockSelection(intersectingYRange: 11..<23, document: document)
        )
        let partialOverlap = try #require(
            blockLayout.blockSelection(intersectingYRange: 10..<24, document: document)
        )

        // Then
        #expect(middleOnly.blockIDs == [b])
        #expect(middleOnly.anchor == b)
        #expect(middleOnly.focus == b)
        #expect(partialOverlap.blockIDs == [a, b, c])
        #expect(partialOverlap.anchor == a)
        #expect(partialOverlap.focus == c)
    }

    @Test("layout되지 않은 y 범위 block selection은 선택을 만들지 않는다")
    func yRangeSelectionRequiresHeightIndex() {
        // Given
        let document = makeFlatDocument([Block(id: "a"), Block(id: "b")])
        let blockLayout = BlockLayout()

        // When
        let selection = blockLayout.blockSelection(intersectingYRange: 0..<10, document: document)

        // Then
        #expect(selection == nil)
    }
}
