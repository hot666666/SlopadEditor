@testable import SlopadEditorBlockLayout
import SlopadEditorCoreModel
import Testing

@Suite("블록 마커 시퀀스 reuse")
struct BlockMarkerSequenceReuseTests {
    @Test("구조 편집에서 생략된 marker entry는 marker block 전환 시 삽입된다")
    func omittedMarkerEntryIsInsertedWhenBlockStartsProducingMarker() throws {
        // Given
        let a: BlockID = "a"
        let inserted: BlockID = "inserted"
        let b: BlockID = "b"
        let oldDocument = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "a")),
            Block(id: b, content: BlockContent(text: "b")),
        ])
        let nextDocument = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "a")),
            Block(
                id: inserted,
                kind: .unorderedListItem,
                content: BlockContent(text: "inserted")
            ),
            Block(id: b, content: BlockContent(text: "b")),
        ])
        var markerSequence = BlockMarkerSequence(
            document: oldDocument,
            visibleIndex: VisibleBlockIndex(document: oldDocument)
        )
        let visibleIndex = VisibleBlockIndex(document: nextDocument)

        // When
        let didRefresh = markerSequence.refreshIndependentMarkers(
            blockIDs: [inserted],
            document: nextDocument,
            visibleIndex: visibleIndex
        )

        // Then
        #expect(didRefresh)
        #expect(markerSequence.markerKind(for: inserted) == .unorderedListItem)
    }

    @Test("marker refresh 생략 가능 여부는 기존 marker와 변경 block kind로 결정된다")
    func markerRefreshReuseDependsOnExistingMarkersAndChangedKinds() {
        // Given
        let a: BlockID = "a"
        let inserted: BlockID = "inserted"
        let markerFreeDocument = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "a")),
        ])
        let plainDocument = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "a")),
            Block(id: inserted, content: BlockContent(text: "inserted")),
        ])
        let markerProducingDocument = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "a")),
            Block(
                id: inserted,
                kind: .unorderedListItem,
                content: BlockContent(text: "inserted")
            ),
        ])
        let existingMarkerDocument = makeFlatDocument([
            Block(id: a, kind: .todo(isChecked: false), content: BlockContent(text: "a")),
            Block(id: inserted, content: BlockContent(text: "inserted")),
        ])
        let changeSet = BlockLayoutChangeSet(insertedBlockIDs: [inserted])
        let markerFreeSequence = BlockMarkerSequence(
            document: markerFreeDocument,
            visibleIndex: VisibleBlockIndex(document: markerFreeDocument)
        )
        let existingMarkerSequence = BlockMarkerSequence(
            document: existingMarkerDocument,
            visibleIndex: VisibleBlockIndex(document: existingMarkerDocument)
        )

        // When
        let canReuseForPlainInsert = markerFreeSequence.canReuseWithoutMarkerRefresh(
            after: changeSet,
            document: plainDocument
        )
        let canReuseForMarkerInsert = markerFreeSequence.canReuseWithoutMarkerRefresh(
            after: changeSet,
            document: markerProducingDocument
        )
        let canReuseWithExistingMarker = existingMarkerSequence.canReuseWithoutMarkerRefresh(
            after: changeSet,
            document: existingMarkerDocument
        )

        // Then
        #expect(canReuseForPlainInsert)
        #expect(!canReuseForMarkerInsert)
        #expect(!canReuseWithExistingMarker)
    }
}
