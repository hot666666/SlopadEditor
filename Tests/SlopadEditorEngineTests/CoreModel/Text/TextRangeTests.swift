@testable import SlopadCoreModel
import Testing

@Suite("텍스트 범위")
struct TextRangeTests {
    @Test("범위 조회는 길이, 포함, 교차 여부를 명확히 반환한다")
    func givenRange_whenQueried_thenLengthContainmentAndIntersectionAreExplicit() {
        // Given
        let range = TextRange(2, 5)

        // When
        let length = range.length
        let isEmpty = range.isEmpty
        let containsLowerBound = range.contains(2)
        let containsUpperBound = range.contains(5)
        let containsNestedRange = range.contains(TextRange(3, 5))
        let intersectsOverlap = range.intersects(TextRange(4, 8))
        let intersectsAdjacent = range.intersects(TextRange(5, 8))
        let isAdjacent = range.isAdjacent(to: TextRange(5, 8))

        // Then
        #expect(length == 3)
        #expect(!isEmpty)
        #expect(containsLowerBound)
        #expect(!containsUpperBound)
        #expect(containsNestedRange)
        #expect(intersectsOverlap)
        #expect(!intersectsAdjacent)
        #expect(isAdjacent)
    }

    @Test("범위를 clamping하면 content bounds 안에 머문다")
    func givenOutOfBoundsRange_whenClamped_thenItStaysInsideContentBounds() {
        // Given
        let partiallyOutOfBounds = TextRange(3, 10)
        let fullyOutOfBounds = TextRange(8, 10)

        // When
        let clampedPartial = partiallyOutOfBounds.clamped(to: 5)
        let clampedFull = fullyOutOfBounds.clamped(to: 5)

        // Then
        #expect(clampedPartial == TextRange(3, 5))
        #expect(clampedFull == TextRange(5, 5))
    }

    @Test("grapheme offset으로 substring을 읽으면 문자 경계를 사용한다")
    func givenGraphemeOffsets_whenSubstringIsRead_thenCharacterBoundariesAreUsed() {
        // Given
        let text = "a한b"

        // When
        let count = text.count
        let suffixFromKoreanCharacter = text.substring(in: TextRange(1, 3))
        let clampedSuffix = text.substring(in: TextRange(2, 99))

        // Then
        #expect(count == 3)
        #expect(suffixFromKoreanCharacter == "한b")
        #expect(clampedSuffix == "b")
    }

    @Test("범위를 shift하면 양쪽 bound가 같은 delta만큼 이동한다")
    func givenRange_whenShifted_thenBothBoundsMoveBySameDelta() {
        // Given
        let range = TextRange(2, 5)

        // When
        let shifted = range.shifted(by: 3)

        // Then
        #expect(shifted == TextRange(5, 8))
    }
}
