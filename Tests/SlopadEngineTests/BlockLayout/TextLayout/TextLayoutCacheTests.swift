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

    @Test("내용이 같으면 revision이 달라도 다시 측정하지 않는다")
    func identicalContentReusesTheMeasurement() {
        // Given: revision 은 "무언가 바뀌었을 것"이라는 규약이지 사실이 아니다. 키가 요청
        // 값이 된 뒤로는 같은 텍스트·같은 폭·같은 종류면 같은 측정값이므로 다시 잴 이유가 없다.
        var cache = TextLayoutCache()
        let first = makeTextLayoutCacheInput(blockID: "a", text: "A", contentRevision: 1)
        let second = makeTextLayoutCacheInput(blockID: "a", text: "A", contentRevision: 2)
        let expected = BlockMeasurement(height: 20)
        let textLayouter = RecordingBlockTextLayouter(measurementsByBlockID: ["a": expected])

        // When
        let measurements = [
            measure(first, cache: &cache, textLayouter: textLayouter),
            measure(second, cache: &cache, textLayouter: textLayouter),
            measure(first, cache: &cache, textLayouter: textLayouter),
        ]

        // Then
        #expect(measurements == [expected, expected, expected])
        #expect(textLayouter.measuredBlockIDs == ["a"])
    }

    @Test("내용이 다르면 revision이 같아도 다시 측정한다")
    func differentContentIsMeasuredAgain() {
        // Given: 이것이 revision 키로는 보장되지 않던 방향이다. 새로 만든 문서는 revision 이
        // 0 부터 다시 시작하므로, 같은 blockID·같은 revision 을 가진 다른 내용이 이전
        // 측정값을 그대로 돌려받을 수 있었다.
        var cache = TextLayoutCache()
        let short = makeTextLayoutCacheInput(blockID: "a", text: "A", contentRevision: 0)
        let long = makeTextLayoutCacheInput(blockID: "a", text: "much longer", contentRevision: 0)
        let textLayouter = RecordingBlockTextLayouter(measurementsByBlockID: [
            "a": BlockMeasurement(height: 20)
        ])

        // When
        _ = measure(short, cache: &cache, textLayouter: textLayouter)
        _ = measure(long, cache: &cache, textLayouter: textLayouter)

        // Then
        #expect(textLayouter.measuredBlockIDs == ["a", "a"])
    }

    @Test("inline mark만 달라도 다시 측정한다")
    func differentMarksAreMeasuredAgain() {
        // Given: chrome signature 문자열은 BlockKind 만 담았기 때문에 mark 변화는 오직
        // contentRevision 을 통해서만 키에 들어왔다.
        var cache = TextLayoutCache()
        let plain = makeTextLayoutCacheInput(blockID: "a", text: "AB", contentRevision: 0)
        let marked = makeTextLayoutCacheInput(
            blockID: "a",
            text: "AB",
            contentRevision: 0,
            marks: [BlockContent.InlineMark(kind: .strong, range: TextRange(0, 1))]
        )
        let textLayouter = RecordingBlockTextLayouter(measurementsByBlockID: [
            "a": BlockMeasurement(height: 20)
        ])

        // When
        _ = measure(plain, cache: &cache, textLayouter: textLayouter)
        _ = measure(marked, cache: &cache, textLayouter: textLayouter)

        // Then
        #expect(textLayouter.measuredBlockIDs == ["a", "a"])
    }
}

// MARK: - Text Layout Cache Fixture

private func makeTextLayoutCacheInput(
    blockID: BlockID,
    text: String,
    contentRevision: Int = 0,
    marks: [BlockContent.InlineMark] = []
) -> (
    block: Block,
    visibleBlock: VisibleBlock,
    contentSnapshot: EffectiveDocumentSnapshot,
    availableWidth: Double,
    textLayoutRevision: Int
) {
    let kind = BlockKind.paragraph
    var content = BlockContent(text: text, marks: marks)
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
    textLayouter: any BlockMeasuring
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
