import Testing

import SlopadCoreModel

@Suite("TextSelection 값")
struct TextSelectionTests {
    @Test("역방향 단일 블록 텍스트 선택은 범위 요청 시 offset을 정규화한다")
    func givenReversedSingleBlockTextSelection_whenRangeIsRequested_thenOffsetsNormalize() {
        // Given
        let selection = TextSelection(
            anchor: TextPosition(blockID: "a", offset: 8),
            focus: TextPosition(blockID: "a", offset: 2)
        )

        // When
        let isSingleBlock = selection.isSingleBlock
        let range = selection.rangeInSingleBlock

        // Then
        #expect(isSingleBlock)
        #expect(range == TextRange(2, 8))
    }

    @Test("여러 블록 텍스트 선택은 단일 블록 범위를 반환하지 않는다")
    func givenMultiBlockTextSelection_whenRangeIsRequested_thenNilIsReturned() {
        // Given
        let selection = TextSelection(
            anchor: TextPosition(blockID: "a", offset: 0),
            focus: TextPosition(blockID: "b", offset: 1)
        )

        // When
        let isSingleBlock = selection.isSingleBlock
        let range = selection.rangeInSingleBlock

        // Then
        #expect(!isSingleBlock)
        #expect(range == nil)
    }
}
