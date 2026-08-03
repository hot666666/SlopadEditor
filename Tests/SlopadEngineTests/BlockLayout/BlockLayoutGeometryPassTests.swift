import Testing

@testable import SlopadBlockLayout
import SlopadCoreModel

@Suite("BlockLayout geometry pass 검증")
struct BlockLayoutGeometryPassTests {
    @Test("BlockLayout은 주어진 block들로 현재 geometry를 만든다")
    func blockLayoutBuildsCurrentGeometryForBlocks() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "BB")),
        ])
        let visibleIndex = VisibleBlockIndex(document: document)
        let layoutInput = makeBlockLayoutTestInput(
            document: document,
            visibleIndex: visibleIndex,
            availableWidth: 300
        )
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()
        let expectedBlockIDs = [a, b]
        let expectedHeights = [11.0, 12.0]
        let expectedTextLayoutRevision = 0

        // When
        _ = runBlockLayoutPass(&blockLayout, input: layoutInput, textLayouter: textLayouter)
        let currentGeometries = blockLayout.visibleGeometries(yOffset: 0, viewportHeight: 23)

        // Then
        #expect(currentGeometries.map(\.blockID) == expectedBlockIDs)
        #expect(currentGeometries.map(\.height) == expectedHeights)
        #expect(blockLayout.textLayoutRevision == expectedTextLayoutRevision)
    }

    @Test("전체 layout pass가 visible 순서대로 측정하고 current geometry를 만든다")
    func fullLayoutPassMeasuresVisibleBlocksAndBuildsCurrentGeometry() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "BB")),
            Block(id: c, content: BlockContent(text: "CCC")),
        ])
        let visibleIndex = VisibleBlockIndex(document: document)
        let availableWidth = 300.0
        let widthRevision = 300
        let layoutInput = makeBlockLayoutTestInput(
            document: document,
            visibleIndex: visibleIndex,
            availableWidth: availableWidth,
            widthRevision: widthRevision
        )
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()
        let expectedBlockIDs = [a, b, c]
        let expectedHeights = [11.0, 12.0, 13.0]
        let expectedTotalHeight: Double = 11 + 12 + 13
        let expectedRevision = EditorSnapshotRevision(
            documentRevision: document.revision,
            compositionRevision: 0,
            textLayoutRevision: 0,
            widthRevision: widthRevision,
            visibleSequenceRevision: visibleIndex.revision
        )

        // When
        let revision = runBlockLayoutPass(
            &blockLayout,
            input: layoutInput,
            textLayouter: textLayouter
        )

        // Then
        let currentGeometries = blockLayout.visibleGeometries(
            yOffset: 0,
            viewportHeight: expectedTotalHeight
        )
        #expect(currentGeometries.map(\.blockID) == expectedBlockIDs)
        #expect(currentGeometries.map(\.height) == expectedHeights)
        #expect(blockLayout.totalHeight == expectedTotalHeight)
        #expect(revision == expectedRevision)
    }

    @Test("드롭 target 조회는 y 위치의 block 또는 문서 끝 이후 마지막 block을 기준으로 indicator를 만든다")
    func dropTargetBlockIDUsesCurrentGeometry() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let viewportWidth = 300.0
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "BB")),
        ])
        let layoutInput = makeBlockLayoutTestInput(
            document: document,
            availableWidth: viewportWidth
        )
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()
        let expectedInsideFirst = BlockDropTarget(blockID: a, placement: .before)
        let expectedAfterEnd = BlockDropTarget(blockID: b, placement: .after)

        // When
        _ = runBlockLayoutPass(&blockLayout, input: layoutInput, textLayouter: textLayouter)
        let expectedAfterEndIndicator = EditorRect(
            x: 0,
            y: blockLayout.totalHeight - 1,
            width: viewportWidth,
            height: 2
        )
        let insideFirst = blockLayout.blockDropTarget(atY: 0, viewportWidth: viewportWidth)
        let afterEnd = blockLayout.blockDropTarget(
            atY: blockLayout.totalHeight + 20,
            viewportWidth: viewportWidth
        )

        // Then
        #expect(insideFirst?.target == expectedInsideFirst)
        #expect(afterEnd?.target == expectedAfterEnd)
        #expect(afterEnd?.indicator == expectedAfterEndIndicator)
    }

    @Test("dirty block relayout은 incremental layout input으로 현재 geometry를 갱신한다")
    func dirtyBlockRelayoutUsesIncrementalLayoutInput() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let initialDocument = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "BB")),
        ])
        var changedDocument = initialDocument
        try changedDocument.updateContent(blockID: b) { content in
            content.insert("BBB", at: content.length)
        }.get()
        let availableWidth = 300.0
        let initialInput = makeBlockLayoutTestInput(
            document: initialDocument,
            availableWidth: availableWidth
        )
        let changedVisibleIndex = VisibleBlockIndex(document: changedDocument)
        let incrementalInput = makeBlockLayoutTestInput(
            document: changedDocument,
            visibleIndex: changedVisibleIndex,
            availableWidth: availableWidth
        )
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()
        _ = runBlockLayoutPass(&blockLayout, input: initialInput, textLayouter: textLayouter)
        textLayouter.measuredBlockIDs.removeAll()
        let expectedBlockIDs = [a, b]
        let expectedHeights = [11.0, 15.0]
        let expectedTotalHeight = 26.0

        // When
        let revisionResult = runBlockLayoutIncrementalPass(
            &blockLayout,
            input: incrementalInput,
            blockIDs: [b],
            textLayouter: textLayouter
        )
        let revision = try #require(revisionResult)
        let currentGeometries = blockLayout.visibleGeometries(
            yOffset: 0,
            viewportHeight: expectedTotalHeight
        )

        // Then
        #expect(revision.documentRevision == changedDocument.revision)
        #expect(textLayouter.measuredBlockIDs == [b])
        #expect(currentGeometries.map(\.blockID) == expectedBlockIDs)
        #expect(currentGeometries.map(\.height) == expectedHeights)
        #expect(blockLayout.totalHeight == expectedTotalHeight)
    }

    @Test("이후 layout pass가 BlockLayout current geometry를 교체한다")
    func laterLayoutPassReplacesCurrentGeometryIndex() {
        // Given
        let firstA: BlockID = "a"
        let firstB: BlockID = "b"
        let secondX: BlockID = "x"
        let firstDocument = makeFlatDocument([
            Block(id: firstA, content: BlockContent(text: "A")),
            Block(id: firstB, content: BlockContent(text: "BB")),
        ])
        let secondDocument = makeFlatDocument([
            Block(id: secondX, content: BlockContent(text: "XXXXXXXXXX"))
        ])
        let firstLayoutInput = makeBlockLayoutTestInput(document: firstDocument, availableWidth: 300)
        let secondLayoutInput = makeBlockLayoutTestInput(
            document: secondDocument,
            availableWidth: 300
        )
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()
        let expectedBlockIDs = [secondX]
        let expectedHeights = [20.0]
        let expectedSecondTotalHeight = 20.0

        // When
        _ = runBlockLayoutPass(&blockLayout, input: firstLayoutInput, textLayouter: textLayouter)
        _ = runBlockLayoutPass(&blockLayout, input: secondLayoutInput, textLayouter: textLayouter)

        // Then
        let currentGeometries = blockLayout.visibleGeometries(
            yOffset: 0,
            viewportHeight: expectedSecondTotalHeight
        )
        #expect(currentGeometries.map(\.blockID) == expectedBlockIDs)
        #expect(currentGeometries.map(\.height) == expectedHeights)
        #expect(blockLayout.totalHeight == expectedSecondTotalHeight)
    }
}
