@testable import SlopadEditorBlockLayout
import SlopadCoreModel
import Testing

func assertItemsInOrder(
    _ index: BlockHeightIndexStorage,
    equal expectedItems: [BlockHeightIndexStorage.Entry]
) {
    #expect(index.count == expectedItems.count)
    let actualItems = (0..<index.count).compactMap { index.entry(at: $0) }
    #expect(actualItems.count == expectedItems.count)
    for (actualItem, expectedItem) in zip(actualItems, expectedItems) {
        assertEntry(actualItem, equal: expectedItem)
    }
}

func assertEntry(
    _ actual: BlockHeightIndexStorage.Entry?,
    equal expected: BlockHeightIndexStorage.Entry?
) {
    switch (actual, expected) {
    case let (actual?, expected?):
        #expect(actual.blockID == expected.blockID)
        #expect(actual.height == expected.height)
    case (nil, nil):
        break
    case (.some, nil), (nil, .some):
        #expect(Bool(false))
    }
}

func assertIndexInvariantsHold(_ index: BlockHeightIndexStorage) {
    #if DEBUG
        #expect(index.validateInvariantsForTesting())
    #endif
}
