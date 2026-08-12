@testable import SlopadEditorEngine
import SlopadCoreModel
import Testing

@Suite("EditorUpdate invalidation 계산")
struct EditorUpdateInvalidationTests {
    @Test("visible 변경 사실은 host invalidation의 sequence 변경으로 접힌다")
    func givenVisibleChangeFacts_whenUpdateInvalidationIsMade_thenSequenceIsInvalidated() {
        // Given
        let invalidation = EditorUpdateInvalidation(
            blockIDs: ["a"],
            visibleSequenceChanged: true
        )

        // When
        let visibleSequenceChanged = invalidation.visibleSequenceChanged

        // Then
        #expect(invalidation.blockIDs == Set(["a"]))
        #expect(visibleSequenceChanged)
        #expect(!invalidation.layoutGeometryChanged)
    }

    @Test("union은 update damage 범위를 보수적으로 합친다")
    func givenInvalidations_whenUnioned_thenDamageFactsAreMerged() {
        // Given
        var invalidation = EditorUpdateInvalidation(
            blockIDs: ["a"],
            visibleSequenceChanged: true
        )
        let other = EditorUpdateInvalidation(
            blockIDs: ["c"],
            layoutGeometryChanged: true
        )

        // When
        invalidation.formUnion(other)

        // Then
        #expect(invalidation.blockIDs == Set(["a", "c"]))
        #expect(invalidation.visibleSequenceChanged)
        #expect(invalidation.layoutGeometryChanged)
    }

}
