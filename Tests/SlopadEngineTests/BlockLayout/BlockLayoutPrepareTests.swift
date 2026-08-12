import Testing

@testable import SlopadEditorBlockLayout
import SlopadCoreModel

@Suite("BlockLayout prepare orchestration 동작")
struct BlockLayoutPrepareTests {
    @Test("텍스트 변경 transaction은 visible 순서를 유지하고 변경 블록만 다시 측정한다")
    func textChangeTransactionRelayoutsDirtyBlock() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        var document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "BBB")),
        ])
        let viewport = EditorViewport(width: 300, scrollY: 0, height: 400)
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()
        let initialRevision = blockLayout.prepare(
            document: document,
            composition: nil,
            viewport: viewport,
            textLayouter: textLayouter
        )
        let initialBlockIDs = blockLayout.allVisibleBlockSelection(document: document)?.blockIDs
        textLayouter.measuredBlockIDs.removeAll()

        // When
        try document.updateContent(blockID: a) { content in
            content.insert("!", at: 1)
        }.get()
        let invalidation = BlockLayoutInvalidation(
            blockIDs: [a]
        )
        blockLayout.markDirty(invalidation)
        let updatedRevision = blockLayout.prepare(
            document: document,
            composition: nil,
            viewport: viewport,
            textLayouter: textLayouter
        )
        let updatedBlockIDs = blockLayout.allVisibleBlockSelection(document: document)?.blockIDs

        // Then
        #expect(invalidation.visibleSequenceChanged == false)
        #expect(blockLayout.isDirty == false)
        #expect(initialBlockIDs == [a, b])
        #expect(updatedBlockIDs == [a, b])
        #expect(updatedRevision.documentRevision == document.revision)
        #expect(updatedRevision.visibleSequenceRevision == initialRevision.visibleSequenceRevision)
        #expect(textLayouter.measuredBlockIDs == [a])
        #expect(blockLayout.blockGeometry(for: a)?.height == 12)
        #expect(blockLayout.blockGeometry(for: b)?.height == 13)
    }

    @Test("구조 변경 transaction은 BlockLayout 안에서 visible 순서와 height index를 갱신한다")
    func structuralTransactionUpdatesVisibleOrderAndHeightIndex() throws {
        // Given
        let a: BlockID = "a"
        let created: BlockID = "created"
        var document = Document.singleParagraph("AB", id: a)
        let viewport = EditorViewport(width: 300, scrollY: 0, height: 400)
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()
        let initialRevision = blockLayout.prepare(
            document: document,
            composition: nil,
            viewport: viewport,
            textLayouter: textLayouter
        )
        let initialBlockIDs = blockLayout.allVisibleBlockSelection(document: document)?.blockIDs
        let initialVisibleSequenceRevision = initialRevision.visibleSequenceRevision

        // When
        _ = try document.splitBlock(blockID: a, offset: 1, newBlockID: created).get()
        let invalidation = BlockLayoutInvalidation(
            blockIDs: [a, created],
            layoutGeometryChanged: true,
            mutations: [.splitBlock(original: a, created: created)]
        )
        blockLayout.markDirty(invalidation)
        let updatedRevision = blockLayout.prepare(
            document: document,
            composition: nil,
            viewport: viewport,
            textLayouter: textLayouter
        )
        let updatedBlockIDs = blockLayout.allVisibleBlockSelection(document: document)?.blockIDs

        // Then
        #expect(invalidation.visibleSequenceChanged == true)
        #expect(invalidation.layoutGeometryChanged == true)
        #expect(blockLayout.isDirty == false)
        #expect(initialBlockIDs == [a])
        #expect(updatedBlockIDs == [a, created])
        #expect(updatedRevision.visibleSequenceRevision != initialVisibleSequenceRevision)
        #expect(blockLayout.blockGeometry(for: created) != nil)
        #expect(blockLayout.blockID(atY: 0) == a)
        #expect(blockLayout.blockID(atY: 11) == created)
        #expect(blockLayout.totalHeight == 22)
    }

    @Test("prepare 후 visible 순서는 BlockLayout projection으로 조회된다")
    func preparedVisibleOrderIsExposedThroughBlockLayoutProjection() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "a")),
            Block(id: b, content: BlockContent(text: "b")),
        ])
        let viewport = EditorViewport(width: 300, scrollY: 0, height: 400)
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()

        // When
        _ = blockLayout.prepare(
            document: document,
            composition: nil,
            viewport: viewport,
            textLayouter: textLayouter
        )
        let projectedBlockIDs = blockLayout.allVisibleBlockSelection(document: document)?.blockIDs

        // Then
        #expect(projectedBlockIDs == [a, b])
    }

    @Test("큰 문서 initial prepare는 현재 viewport 주변 block만 정확히 측정한다")
    func largeInitialPrepareMeasuresViewportRangeOnly() {
        // Given
        let blockCount = 600
        let document = makeFlatDocument(
            (0..<blockCount).map { index in
                Block(id: BlockID("block-\(index)"), content: BlockContent(text: "x"))
            }
        )
        let viewport = EditorViewport(width: 300, scrollY: 300 * 36, height: 120)
        let textLayouter = RecordingBlockTextLayouter(fallbackBaseHeight: 35)
        var blockLayout = BlockLayout()

        // When
        _ = blockLayout.prepare(
            document: document,
            composition: nil,
            viewport: viewport,
            textLayouter: textLayouter
        )
        let renderedGeometries = blockLayout.visibleGeometries(
            yOffset: viewport.scrollY,
            viewportHeight: viewport.height
        )
        let measuredBlockIDs = Set(textLayouter.measuredBlockIDs)

        // Then
        #expect(!renderedGeometries.isEmpty)
        #expect(textLayouter.measuredBlockIDs.count < blockCount)
        #expect(textLayouter.measuredBlockIDs.count >= renderedGeometries.count)
        #expect(renderedGeometries.allSatisfy { measuredBlockIDs.contains($0.blockID) })
    }

    @Test("큰 문서 scroll prepare는 아직 측정하지 않은 viewport block을 demand measure한다")
    func scrolledLargePrepareMeasuresDemandViewportRange() {
        // Given
        let blockCount = 600
        let document = makeFlatDocument(
            (0..<blockCount).map { index in
                Block(id: BlockID("block-\(index)"), content: BlockContent(text: "x"))
            }
        )
        let topViewport = EditorViewport(width: 300, scrollY: 0, height: 120)
        let scrolledViewport = EditorViewport(width: 300, scrollY: 300 * 36, height: 120)
        let textLayouter = RecordingBlockTextLayouter(fallbackBaseHeight: 35)
        var blockLayout = BlockLayout()
        _ = blockLayout.prepare(
            document: document,
            composition: nil,
            viewport: topViewport,
            textLayouter: textLayouter
        )
        textLayouter.measuredBlockIDs.removeAll()

        // When
        _ = blockLayout.prepare(
            document: document,
            composition: nil,
            viewport: scrolledViewport,
            textLayouter: textLayouter
        )
        let renderedGeometries = blockLayout.visibleGeometries(
            yOffset: scrolledViewport.scrollY,
            viewportHeight: scrolledViewport.height
        )
        let measuredBlockIDs = Set(textLayouter.measuredBlockIDs)

        // Then
        #expect(!renderedGeometries.isEmpty)
        #expect(!textLayouter.measuredBlockIDs.isEmpty)
        #expect(textLayouter.measuredBlockIDs.count < blockCount)
        #expect(renderedGeometries.allSatisfy { measuredBlockIDs.contains($0.blockID) })
    }

    @Test("ordered block split 후 marker state는 BlockLayout geometry output에서 갱신된다")
    func orderedSplitUpdatesMarkerStateInBlockLayoutGeometryOutput() throws {
        // Given
        let blockID: BlockID = "ordered"
        let created: BlockID = "ordered-created"
        var document = Document.singleParagraph("ab", id: blockID)
        try document.setBlockKind(blockID: blockID, kind: .orderedListItem(restartNumber: 10)).get()
        let viewport = EditorViewport(width: 300, scrollY: 0, height: 400)
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()

        // When
        _ = try document.splitBlock(blockID: blockID, offset: 1, newBlockID: created).get()
        blockLayout.markDirty(
            BlockLayoutInvalidation(
                blockIDs: [blockID, created],
                layoutGeometryChanged: true,
                mutations: [.splitBlock(original: blockID, created: created)]
            )
        )
        _ = blockLayout.prepare(
            document: document,
            composition: nil,
            viewport: viewport,
            textLayouter: textLayouter
        )

        // Then
        #expect(
            blockLayout.blockGeometry(for: blockID)?.markerKind == .orderedListItem(number: 10)
        )
        #expect(
            blockLayout.blockGeometry(for: created)?.markerKind == .orderedListItem(number: 11)
        )
    }
}
