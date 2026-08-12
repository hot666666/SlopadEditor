import Testing

import SlopadCoreModel

@Suite("텍스트 조합")
struct TextCompositionTests {
    @Test("텍스트 조합 revision은 composition revision으로 반환된다")
    func givenTextComposition_whenRevisionIsRead_thenCompositionRevisionIsReturned() {
        // Given
        let composition = TextComposition(
            blockID: "a",
            replacementRange: TextRange.point(0),
            text: "Hello",
            revision: 3
        )

        // When
        let revision = composition.compositionRevision

        // Then
        #expect(revision == 3)
    }

    @Test("내부 composition revision은 public equality에 노출되지 않는다")
    func givenDifferentInternalRevisions_whenCompared_thenPublicCompositionIsStable() {
        // Given
        let first = TextComposition(
            blockID: "a",
            replacementRange: TextRange.point(0),
            text: "Hello",
            revision: 1
        )
        let second = TextComposition(
            blockID: "a",
            replacementRange: TextRange.point(0),
            text: "Hello",
            revision: 2
        )

        // When
        let uniqueCompositions = Set([first, second])

        // Then
        #expect(first == second)
        #expect(uniqueCompositions.count == 1)
    }
}
