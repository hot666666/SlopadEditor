import Testing

@testable import SlopadBlockLayout
import SlopadCoreModel

@Suite("TextLayout cache 정책")
struct TextLayoutCacheTests {
    @Test("같은 measurement key는 측정 결과를 재사용한다")
    func sameMeasurementKeyReusesCachedMeasurement() {
        // Given
        var cache = TextLayoutCache()
        let input = makeTextLayoutCacheInput(blockID: "a", text: "A")
        let expectedMeasurement = BlockMeasurement(height: 20)
        let textLayouter = RecordingBlockTextLayouter(measurementsByBlockID: [
            "a": expectedMeasurement
        ])
        let expectedMeasurements = [
            expectedMeasurement,
            expectedMeasurement,
        ]
        let expectedMeasuredBlockIDs: [BlockID] = ["a"]

        // When
        let measurements = [
            measure(input, cache: &cache, textLayouter: textLayouter),
            measure(input, cache: &cache, textLayouter: textLayouter),
        ]

        // Then
        #expect(measurements == expectedMeasurements)
        #expect(textLayouter.measuredBlockIDs == expectedMeasuredBlockIDs)
    }

    @Test("blockID 무효화는 해당 block 측정값만 제거한다")
    func invalidateBlockIDRemovesOnlyMatchingMeasurement() {
        // Given
        var cache = TextLayoutCache()
        let aInput = makeTextLayoutCacheInput(blockID: "a", text: "A")
        let bInput = makeTextLayoutCacheInput(blockID: "b", text: "BB")
        let invalidatedBlockIDA: BlockID = "a"
        let expectedAMeasurement = BlockMeasurement(height: 20)
        let expectedBMeasurement = BlockMeasurement(height: 30)
        let textLayouter = RecordingBlockTextLayouter(measurementsByBlockID: [
            "a": expectedAMeasurement,
            "b": expectedBMeasurement,
        ])
        let expectedMeasurementsAfterInvalidation = [
            expectedAMeasurement,
            expectedBMeasurement,
        ]
        let expectedMeasuredBlockIDs: [BlockID] = ["a", "b", "a"]

        // When
        _ = measure(aInput, cache: &cache, textLayouter: textLayouter)
        _ = measure(bInput, cache: &cache, textLayouter: textLayouter)
        cache.invalidate(blockID: invalidatedBlockIDA)
        let measurementsAfterInvalidation = [
            measure(aInput, cache: &cache, textLayouter: textLayouter),
            measure(bInput, cache: &cache, textLayouter: textLayouter),
        ]

        // Then
        #expect(measurementsAfterInvalidation == expectedMeasurementsAfterInvalidation)
        #expect(textLayouter.measuredBlockIDs == expectedMeasuredBlockIDs)
    }

    @Test("전체 무효화는 모든 cached measurement를 제거한다")
    func invalidateAllRemovesEveryMeasurement() {
        // Given
        var cache = TextLayoutCache()
        let inputs = [
            makeTextLayoutCacheInput(blockID: "a", text: "A"),
            makeTextLayoutCacheInput(blockID: "b", text: "BB"),
        ]
        let expectedAMeasurement = BlockMeasurement(height: 20)
        let expectedBMeasurement = BlockMeasurement(height: 30)
        let textLayouter = RecordingBlockTextLayouter(measurementsByBlockID: [
            "a": expectedAMeasurement,
            "b": expectedBMeasurement,
        ])
        let expectedMeasurementsAfterInvalidation = [
            expectedAMeasurement,
            expectedBMeasurement,
        ]
        let expectedMeasuredBlockIDs: [BlockID] = ["a", "b", "a", "b"]

        // When
        for input in inputs {
            _ = measure(input, cache: &cache, textLayouter: textLayouter)
        }
        cache.invalidateAll()
        let measurementsAfterInvalidation = inputs.map {
            measure($0, cache: &cache, textLayouter: textLayouter)
        }

        // Then
        #expect(measurementsAfterInvalidation == expectedMeasurementsAfterInvalidation)
        #expect(textLayouter.measuredBlockIDs == expectedMeasuredBlockIDs)
    }

    @Test("contentRevision이 다르면 같은 blockID도 별도 측정값으로 본다")
    func differentContentRevisionUsesSeparateMeasurement() {
        // Given
        var cache = TextLayoutCache()
        let firstInput = makeTextLayoutCacheInput(blockID: "a", text: "A", contentRevision: 1)
        let secondInput = makeTextLayoutCacheInput(blockID: "a", text: "A", contentRevision: 2)
        let expectedMeasurement = BlockMeasurement(height: 20)
        let textLayouter = RecordingBlockTextLayouter(measurementsByBlockID: [
            "a": expectedMeasurement
        ])
        let expectedMeasurements = [
            expectedMeasurement,
            expectedMeasurement,
            expectedMeasurement,
        ]
        let expectedMeasuredBlockIDs: [BlockID] = ["a", "a"]

        // When
        let measurements = [
            measure(firstInput, cache: &cache, textLayouter: textLayouter),
            measure(secondInput, cache: &cache, textLayouter: textLayouter),
            measure(firstInput, cache: &cache, textLayouter: textLayouter),
        ]

        // Then
        #expect(measurements == expectedMeasurements)
        #expect(textLayouter.measuredBlockIDs == expectedMeasuredBlockIDs)
    }
}

// MARK: - Text Layout Cache Fixture

private func makeTextLayoutCacheInput(
    blockID: BlockID,
    text: String,
    contentRevision: Int = 0
) -> (
    block: Block,
    visibleBlock: VisibleBlock,
    contentSnapshot: EffectiveDocumentSnapshot,
    availableWidth: Double,
    textLayoutRevision: Int
) {
    let kind = BlockKind.paragraph
    var content = BlockContent(text: text)
    content.revision = contentRevision
    let block = Block(
        id: blockID,
        kind: kind,
        content: content
    )
    let document = makeFlatDocument([block])
    return (
        block: block,
        visibleBlock: VisibleBlock(blockID: blockID, depth: 0, parentID: nil),
        contentSnapshot: EffectiveDocumentSnapshot(document: document),
        availableWidth: 300,
        textLayoutRevision: 0
    )
}

private func measure(
    _ input: (
        block: Block,
        visibleBlock: VisibleBlock,
        contentSnapshot: EffectiveDocumentSnapshot,
        availableWidth: Double,
        textLayoutRevision: Int
    ),
    cache: inout TextLayoutCache,
    textLayouter: any BlockTextLayoutProtocol
) -> BlockMeasurement {
    cache.measurement(
        for: input.block,
        visibleBlock: input.visibleBlock,
        contentSnapshot: input.contentSnapshot,
        availableWidth: input.availableWidth,
        textLayoutRevision: input.textLayoutRevision,
        textLayouter: textLayouter
    )
}
