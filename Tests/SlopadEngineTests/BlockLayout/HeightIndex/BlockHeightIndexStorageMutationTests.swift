import Testing

@testable import SlopadEditorBlockLayout
import SlopadCoreModel

@Suite("BlockHeightIndexStorage 변경")
struct BlockHeightIndexStorageMutationTests {
    @Test("중복 blockID 삽입은 기존 항목을 변경하지 않는다")
    func duplicateBlockIDInsertDoesNotChangeExistingItem() {
        // Given
        let existingBlocks = [
            BlockHeightIndexStorage.Entry(blockID: "a", height: 10),
            BlockHeightIndexStorage.Entry(blockID: "b", height: 20),
            BlockHeightIndexStorage.Entry(blockID: "c", height: 30),
        ]
        let duplicateBlock = BlockHeightIndexStorage.Entry(blockID: "b", height: 99)
        let duplicateInsertionIndex = 0
        let expectedBlocks = existingBlocks
        let index = BlockHeightIndexStorage(entries: existingBlocks)

        // When
        index.insert(duplicateBlock, at: duplicateInsertionIndex)

        // Then
        assertItemsInOrder(index, equal: expectedBlocks)
        assertIndexInvariantsHold(index)
    }

    @Test("없는 blockID 제거 요청은 인덱스를 변경하지 않는다")
    func removingMissingBlockIDDoesNotChangeIndex() {
        // Given
        let existingBlocks = [
            BlockHeightIndexStorage.Entry(blockID: "a", height: 10),
            BlockHeightIndexStorage.Entry(blockID: "b", height: 20),
        ]
        let missingBlockID: BlockID = "missing"
        let expectedRemovedBlock: BlockHeightIndexStorage.Entry? = nil
        let expectedBlocks = existingBlocks
        let index = BlockHeightIndexStorage(entries: existingBlocks)

        // When
        let removed = index.remove(blockID: missingBlockID)

        // Then
        assertEntry(removed, equal: expectedRemovedBlock)
        assertItemsInOrder(index, equal: expectedBlocks)
        assertIndexInvariantsHold(index)
    }

    @Test("없는 blockID 높이 갱신 요청은 인덱스를 변경하지 않는다")
    func updatingMissingBlockIDHeightDoesNotChangeIndex() {
        // Given
        let existingBlocks = [
            BlockHeightIndexStorage.Entry(blockID: "a", height: 10),
            BlockHeightIndexStorage.Entry(blockID: "b", height: 20),
        ]
        let missingBlockID: BlockID = "missing"
        let replacementHeight = 100.0
        let expectedBlocks = existingBlocks
        let expectedTotalHeight = 30.0
        let index = BlockHeightIndexStorage(entries: existingBlocks)

        // When
        index.updateHeight(blockID: missingBlockID, height: replacementHeight)

        // Then
        assertItemsInOrder(index, equal: expectedBlocks)
        #expect(index.totalHeight == expectedTotalHeight)
        assertIndexInvariantsHold(index)
    }

    @Test("높이 갱신이 전체 높이와 topY를 갱신한다")
    func updateHeightChangesTotalHeightAndTopY() {
        // Given
        let blockIDs: [BlockID] = ["a", "b", "c"]
        let existingBlocks = [
            BlockHeightIndexStorage.Entry(blockID: "a", height: 10),
            BlockHeightIndexStorage.Entry(blockID: "b", height: 20),
            BlockHeightIndexStorage.Entry(blockID: "c", height: 30),
        ]
        let updatedBlockID: BlockID = "b"
        let updatedHeight = 50.0
        let expectedTotalHeight =
            existingBlocks[0].height + updatedHeight + existingBlocks[2].height
        let expectedTopYs = [
            0.0,
            existingBlocks[0].height,
            existingBlocks[0].height + updatedHeight,
        ]
        let yOffsets = [59.99, 60]
        let expectedBlockIDs: [BlockID?] = ["b", "c"]
        let index = BlockHeightIndexStorage(entries: existingBlocks)

        // When
        index.updateHeight(blockID: updatedBlockID, height: updatedHeight)
        let topYs = blockIDs.map { index.topY(for: $0) }
        let blockIDsAtY = yOffsets.map { index.blockID(atY: $0) }

        // Then
        #expect(index.totalHeight == expectedTotalHeight)
        #expect(topYs == expectedTopYs)
        #expect(blockIDsAtY == expectedBlockIDs)
        assertIndexInvariantsHold(index)
    }

    @Test("remove가 제거 항목을 반환하고 인덱스에서 제외한다")
    func removeReturnsItemAndDeletesItFromIndex() {
        // Given
        let existingBlocks = [
            BlockHeightIndexStorage.Entry(blockID: "a", height: 10),
            BlockHeightIndexStorage.Entry(blockID: "b", height: 20),
            BlockHeightIndexStorage.Entry(blockID: "c", height: 30),
        ]
        let removedBlockID: BlockID = "b"
        let expectedRemovedBlock = BlockHeightIndexStorage.Entry(blockID: "b", height: 20)
        let expectedBlocks = [
            BlockHeightIndexStorage.Entry(blockID: "a", height: 10),
            BlockHeightIndexStorage.Entry(blockID: "c", height: 30),
        ]
        let expectedRemovedBlockIndex: Int? = nil
        let expectedRemovedBlockTopY: Double? = nil
        let index = BlockHeightIndexStorage(entries: existingBlocks)

        // When
        let removed = index.remove(blockID: removedBlockID)

        // Then
        assertEntry(removed, equal: expectedRemovedBlock)
        assertItemsInOrder(index, equal: expectedBlocks)
        #expect(index.index(of: removedBlockID) == expectedRemovedBlockIndex)
        #expect(index.topY(for: removedBlockID) == expectedRemovedBlockTopY)
        assertIndexInvariantsHold(index)
    }
}
