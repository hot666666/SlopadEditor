import Testing

@testable import SlopadEditorBlockLayout
import SlopadCoreModel

@Suite("BlockHeightIndexStorage 조회")
struct BlockHeightIndexStorageQueryTests {
    @Test("삽입된 블록이 기대 순서로 조회된다")
    func insertedBlocksAreReturnedInExpectedOrder() {
        // Given
        let index = BlockHeightIndexStorage()
        let insertedBlocks = [
            BlockHeightIndexStorage.Entry(blockID: "a", height: 10),
            BlockHeightIndexStorage.Entry(blockID: "b", height: 20),
            BlockHeightIndexStorage.Entry(blockID: "c", height: 5),
        ]
        let expectedBlocks = insertedBlocks

        // When
        for (position, block) in insertedBlocks.enumerated() {
            index.insert(block, at: position)
        }

        // Then
        assertItemsInOrder(index, equal: expectedBlocks)
        assertIndexInvariantsHold(index)
    }

    @Test("blockID 조회가 index와 topY를 반환한다")
    func blockIDLookupReturnsIndexAndTopY() {
        // Given
        let existingBlocks = [
            BlockHeightIndexStorage.Entry(blockID: "a", height: 10),
            BlockHeightIndexStorage.Entry(blockID: "b", height: 20),
            BlockHeightIndexStorage.Entry(blockID: "c", height: 5),
        ]
        let blockIDs: [BlockID] = ["a", "b", "c", "missing"]
        let expectedIndices = [0, 1, 2, nil]
        let expectedTopYs = [0.0, 10, 30, nil]
        let index = BlockHeightIndexStorage(entries: existingBlocks)

        // When
        let indices = blockIDs.map { index.index(of: $0) }
        let topYs = blockIDs.map { index.topY(for: $0) }

        // Then
        #expect(indices == expectedIndices)
        #expect(topYs == expectedTopYs)
        assertIndexInvariantsHold(index)
    }

    @Test("Y 위치 조회가 해당 높이 구간의 blockID를 반환한다")
    func yLookupReturnsBlockIDContainingPosition() {
        // Given
        let existingBlocks = [
            BlockHeightIndexStorage.Entry(blockID: "a", height: 10),
            BlockHeightIndexStorage.Entry(blockID: "b", height: 20),
            BlockHeightIndexStorage.Entry(blockID: "c", height: 5),
        ]
        let yOffsets = [-1, 0, 9.99, 10, 29.99, 30, 34.99, 35]
        let expectedBlockIDs: [BlockID?] = ["a", "a", "a", "b", "b", "c", "c", nil]
        let index = BlockHeightIndexStorage(entries: existingBlocks)

        // When
        let blockIDs = yOffsets.map { index.blockID(atY: $0) }

        // Then
        #expect(blockIDs == expectedBlockIDs)
        assertIndexInvariantsHold(index)
    }

    @Test("viewport 높이 조회가 보이는 index 범위를 반환한다")
    func visibleRangeReturnsIntersectingIndexRange() {
        // Given
        let existingBlocks = [
            BlockHeightIndexStorage.Entry(blockID: "a", height: 10),
            BlockHeightIndexStorage.Entry(blockID: "b", height: 20),
            BlockHeightIndexStorage.Entry(blockID: "c", height: 5),
        ]
        let viewports: [(yOffset: Double, height: Double)] = [
            (yOffset: 0, height: 10),
            (yOffset: 5, height: 20),
            (yOffset: 10, height: 20),
            (yOffset: 30, height: 5),
            (yOffset: 35, height: 10),
            (yOffset: 0, height: 0),
        ]
        let expectedRanges = [
            0..<1,
            0..<2,
            1..<2,
            2..<3,
            3..<3,
            0..<0,
        ]
        let index = BlockHeightIndexStorage(entries: existingBlocks)

        // When
        let ranges = viewports.map {
            index.visibleRange(yOffset: $0.yOffset, viewportHeight: $0.height)
        }

        // Then
        #expect(ranges == expectedRanges)
        assertIndexInvariantsHold(index)
    }
}
