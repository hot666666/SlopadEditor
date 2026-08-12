import Testing

@testable import SlopadEditorBlockLayout
import SlopadCoreModel

@Suite("BlockLayout content revision 전파")
struct BlockLayoutContentRevisionTests {
    @Test("문서 revision 변경이 layout snapshot revision에 반영된다")
    func documentRevisionChangeUpdatesEditorSnapshotRevision() throws {
        // Given
        let a: BlockID = "a"
        var document = Document.singleParagraph("A", id: a)
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()
        let baseLayoutInput = makeBlockLayoutTestInput(document: document, availableWidth: 300)
        let baseRevision = runBlockLayoutPass(
            &blockLayout,
            input: baseLayoutInput,
            textLayouter: textLayouter
        )
        try document.updateContent(blockID: a, { content in
            content.insert("!", at: content.length)
        }).get()
        let changedLayoutInput = makeBlockLayoutTestInput(document: document, availableWidth: 300)
        let expectedDocumentRevision = document.revision

        // When
        let changedRevision = runBlockLayoutPass(
            &blockLayout,
            input: changedLayoutInput,
            textLayouter: textLayouter
        )

        // Then
        #expect(changedRevision.documentRevision == expectedDocumentRevision)
        #expect(changedRevision.documentRevision != baseRevision.documentRevision)
    }

    @Test("composition revision 변경이 layout snapshot revision에 반영된다")
    func compositionRevisionChangeUpdatesEditorSnapshotRevision() {
        // Given
        let a: BlockID = "a"
        let document = Document.singleParagraph("A", id: a)
        let visibleIndex = VisibleBlockIndex(document: document)
        let baseCompositionRevision = 0
        let composition = TextComposition(
            blockID: a,
            replacementRange: TextRange.point(1),
            text: "?",
            revision: 1
        )
        let baseLayoutInput = makeBlockLayoutTestInput(
            document: document,
            visibleIndex: visibleIndex,
            availableWidth: 300
        )
        let changedLayoutInput = makeBlockLayoutTestInput(
            document: document,
            composition: composition,
            visibleIndex: visibleIndex,
            availableWidth: 300
        )
        let textLayouter = RecordingBlockTextLayouter()
        var blockLayout = BlockLayout()
        let expectedCompositionRevision = 1

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
        #expect(baseRevision.compositionRevision == baseCompositionRevision)
        #expect(changedRevision.compositionRevision == expectedCompositionRevision)
    }
}
