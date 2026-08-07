import Testing

import SlopadCoreModel

@Suite("BlockContent editing mutation 동작")
struct BlockContentEditingMutationTests {
    @Test("mark 내부에 텍스트를 삽입하면 mark 범위가 확장된다")
    func givenInsertedTextInsideMark_whenContentMutates_thenMarkExpands() {
        // Given
        var content = BlockContent(
            text: "abcd",
            marks: [BlockContent.InlineMark(kind: .strong, range: TextRange(1, 3))]
        )

        // When
        content.insert("X", at: 2)

        // Then
        #expect(content.text == "abXcd")
        #expect(content.marks == [BlockContent.InlineMark(kind: .strong, range: TextRange(1, 4))])
        #expect(content.revision == 1)
    }

    @Test("mark를 가로지르는 텍스트 삭제는 남은 mark 범위를 재배치한다")
    func givenDeletedTextCrossingMark_whenContentMutates_thenSurvivingMarkRangeIsRemapped() {
        // Given
        var content = BlockContent(
            text: "abcd",
            marks: [BlockContent.InlineMark(kind: .strong, range: TextRange(0, 4))]
        )

        // When
        content.delete(TextRange(1, 3))

        // Then
        #expect(content.text == "ad")
        #expect(content.marks == [BlockContent.InlineMark(kind: .strong, range: TextRange(0, 2))])
        #expect(content.revision == 1)
    }

    @Test("빈 mark 범위를 추가하면 content는 변경되지 않는다")
    func givenEmptyMarkRange_whenMarkIsAdded_thenContentIsUnchanged() {
        // Given
        var content = BlockContent(text: "abcd")

        // When
        content.addMark(kind: .strong, range: TextRange.point(2))

        // Then
        #expect(content.marks.isEmpty)
        #expect(content.revision == 0)
    }
}
