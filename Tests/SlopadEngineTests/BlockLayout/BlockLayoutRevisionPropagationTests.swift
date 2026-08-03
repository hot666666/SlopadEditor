import Testing

@testable import SlopadBlockLayout
import SlopadCoreModel

@Suite("BlockLayout revision 전파")
struct BlockLayoutRevisionPropagationTests {
    @Test("text layout revision 변경이 layout snapshot revision에 반영된다")
    func textLayoutRevisionChangeUpdatesEditorSnapshotRevision() {
        // Given
        let document = Document.singleParagraph("A", id: "a")
        let visibleIndex = VisibleBlockIndex(document: document)
        let layoutInput = makeBlockLayoutTestInput(
            document: document,
            visibleIndex: visibleIndex,
            availableWidth: 300
        )
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()
        let baseTextLayoutRevision = 0

        // When
        let baseRevision = runBlockLayoutPass(
            &blockLayout,
            input: layoutInput,
            textLayouter: textLayouter
        )
        blockLayout.advanceTextLayoutRevision()
        let changedRevision = runBlockLayoutPass(
            &blockLayout,
            input: layoutInput,
            textLayouter: textLayouter
        )

        // Then
        #expect(baseRevision.textLayoutRevision == baseTextLayoutRevision)
        #expect(changedRevision.textLayoutRevision == baseTextLayoutRevision + 1)
    }

    @Test("text layout revision 변경은 lazy layout의 기존 backend 측정값을 제거한다")
    func textLayoutRevisionClearsLazyMeasurements() {
        // Given
        let blockCount = 600
        let document = makeFlatDocument(
            (0..<blockCount).map { index in
                Block(id: BlockID("block-\(index)"), content: BlockContent(text: "x"))
            }
        )
        let viewport = EditorViewport(width: 300, scrollY: 0, height: 120)
        let textLayouter = RecordingBlockTextLayouter(fallbackBaseHeight: 35)
        var blockLayout = BlockLayout()
        _ = blockLayout.prepare(
            document: document,
            composition: nil,
            viewport: viewport,
            textLayouter: textLayouter
        )
        let measuredBeforeChange = blockLayout.measurementsByBlockID

        // When
        blockLayout.advanceTextLayoutRevision()

        // Then
        #expect(!measuredBeforeChange.isEmpty)
        #expect(blockLayout.measurementsByBlockID.isEmpty)
        #expect(blockLayout.isDirty)
    }

    @Test("width revision 변경이 layout snapshot revision에 반영된다")
    func widthRevisionChangeUpdatesEditorSnapshotRevision() {
        // Given
        let document = Document.singleParagraph("A", id: "a")
        let visibleIndex = VisibleBlockIndex(document: document)
        let baseWidthRevision = 300
        let changedWidthRevision = 320
        let baseLayoutInput = makeBlockLayoutTestInput(
            document: document,
            visibleIndex: visibleIndex,
            availableWidth: 300,
            widthRevision: baseWidthRevision
        )
        let changedLayoutInput = makeBlockLayoutTestInput(
            document: document,
            visibleIndex: visibleIndex,
            availableWidth: 320,
            widthRevision: changedWidthRevision
        )
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()

        // When
        let baseRevision = runBlockLayoutPass(
            &blockLayout,
            input: baseLayoutInput,
            textLayouter: textLayouter
        )
        let changedRevision = runBlockLayoutPass(
            &blockLayout,
            input: changedLayoutInput,
            textLayouter: textLayouter
        )

        // Then
        #expect(baseRevision.widthRevision == baseWidthRevision)
        #expect(changedRevision.widthRevision == changedWidthRevision)
    }

    @Test("visible sequence revision 변경이 layout snapshot revision에 반영된다")
    func visibleSequenceRevisionChangeUpdatesEditorSnapshotRevision() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "B")),
        ])
        let baseVisibleIndex = VisibleBlockIndex(
            [VisibleBlock(blockID: a, depth: 0, parentID: nil)],
            revision: 10
        )
        let changedVisibleIndex = VisibleBlockIndex(
            [
                VisibleBlock(blockID: a, depth: 0, parentID: nil),
                VisibleBlock(blockID: b, depth: 0, parentID: nil),
            ],
            revision: 11
        )
        let baseLayoutInput = makeBlockLayoutTestInput(
            document: document,
            visibleIndex: baseVisibleIndex,
            availableWidth: 300
        )
        let changedLayoutInput = makeBlockLayoutTestInput(
            document: document,
            visibleIndex: changedVisibleIndex,
            availableWidth: 300
        )
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()
        let expectedBaseVisibleSequenceRevision = 10
        let expectedChangedVisibleSequenceRevision = 11

        // When
        let baseRevision = runBlockLayoutPass(
            &blockLayout,
            input: baseLayoutInput,
            textLayouter: textLayouter
        )
        let changedRevision = runBlockLayoutPass(
            &blockLayout,
            input: changedLayoutInput,
            textLayouter: textLayouter
        )

        // Then
        #expect(
            baseRevision.visibleSequenceRevision == expectedBaseVisibleSequenceRevision)
        #expect(
            changedRevision.visibleSequenceRevision
                == expectedChangedVisibleSequenceRevision
        )
    }
}
