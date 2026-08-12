import Testing

import SlopadCoreModel

@Suite("BlockSelection 값")
struct BlockSelectionTests {
    @Test("블록 선택은 첫 블록을 anchor, 마지막 블록을 focus 기본값으로 사용한다")
    func givenBlockSelection_whenInitialized_thenAnchorAndFocusDefaultToEdges() {
        // Given
        let blockIDs: [BlockID] = ["a", "b"]

        // When
        let selection = BlockSelection(blockIDs: blockIDs)

        // Then
        #expect(selection.blockIDs == blockIDs)
        #expect(selection.anchor == "a")
        #expect(selection.focus == "b")
    }
}
