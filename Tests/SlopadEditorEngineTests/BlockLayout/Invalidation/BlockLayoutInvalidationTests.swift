@testable import SlopadEditorBlockLayout
import SlopadEditorCoreModel
import Testing

@Suite("BlockLayout invalidation 계산")
struct BlockLayoutInvalidationTests {
    @Test("layout mutation을 가진 invalidation은 rebuild 조건을 계산한다")
    func givenLayoutMutation_whenInvalidationIsMade_thenLayoutFactsAreDerived() {
        // Given
        let invalidation = BlockLayoutInvalidation(
            blockIDs: ["a"],
            layoutGeometryChanged: true,
            mutations: [.splitBlock(original: "a", created: "b")]
        )

        // When
        let visibleSequenceChanged = invalidation.visibleSequenceChanged

        // Then
        #expect(invalidation.blockIDs == Set(["a"]))
        #expect(visibleSequenceChanged)
        #expect(invalidation.layoutGeometryChanged)
        #expect(invalidation.mutations.count == 1)
        guard case .splitBlock(original: "a", created: "b") = invalidation.mutations.first else {
            Issue.record("layout mutation이 splitBlock fact를 유지해야 한다")
            return
        }
    }

    @Test("union은 block 변경과 layout invalidation을 보수적으로 합친다")
    func givenInvalidations_whenUnioned_thenDirtyFactsAreMergedConservatively() {
        // Given
        var invalidation = BlockLayoutInvalidation(
            blockIDs: ["a"],
            mutations: [.splitBlock(original: "a", created: "b")]
        )
        let other = BlockLayoutInvalidation(
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
