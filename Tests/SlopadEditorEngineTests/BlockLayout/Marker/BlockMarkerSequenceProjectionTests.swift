@testable import SlopadEditorBlockLayout
import SlopadEditorCoreModel
import Testing

@Suite("블록 마커 시퀀스 projection")
struct BlockMarkerSequenceProjectionTests {
    @Test("ordered marker는 visible sibling 구조와 restart anchor에서 파생된다")
    func orderedMarkersFollowVisibleSiblingStructureAndRestartAnchors() {
        // Given
        let a: BlockID = "a"
        let childParagraph: BlockID = "childParagraph"
        let b: BlockID = "b"
        let breakBlock: BlockID = "break"
        let c: BlockID = "c"
        let d: BlockID = "d"
        let child1: BlockID = "child1"
        let child2: BlockID = "child2"
        let e: BlockID = "e"
        var document = Document()
        document.appendRoot(orderedMarkerBlock(id: a))
        document.appendChild(Block(id: childParagraph, content: BlockContent(text: "child")), to: a)
        document.appendRoot(orderedMarkerBlock(id: b))
        document.appendRoot(Block(id: breakBlock, content: BlockContent(text: "break")))
        document.appendRoot(orderedMarkerBlock(id: c, restartNumber: 10))
        document.appendRoot(orderedMarkerBlock(id: d))
        document.appendChild(orderedMarkerBlock(id: child1), to: d)
        document.appendChild(orderedMarkerBlock(id: child2), to: d)
        document.appendRoot(orderedMarkerBlock(id: e))
        let visibleIndex = VisibleBlockIndex(document: document)
        let expectedMarkerKinds: [BlockMarkerKind] = [
            .orderedListItem(number: 1),
            .none,
            .orderedListItem(number: 2),
            .none,
            .orderedListItem(number: 10),
            .orderedListItem(number: 11),
            .orderedListItem(number: 1),
            .orderedListItem(number: 2),
            .orderedListItem(number: 12),
        ]

        // When
        let markerSequence = BlockMarkerSequence(
            document: document,
            visibleIndex: visibleIndex
        )

        // Then
        #expect(markerKinds(markerSequence, visibleIndex: visibleIndex) == expectedMarkerKinds)
    }

    @Test("같은 depth의 비 ordered 블록은 ordered sequence를 끊는다")
    func sameDepthNonOrderedBlockSplitsOrderedSequence() {
        // Given
        let a: BlockID = "a"
        let paragraph: BlockID = "paragraph"
        let b: BlockID = "b"
        let document = makeFlatDocument([
            orderedMarkerBlock(id: a),
            Block(id: paragraph, content: BlockContent(text: "break")),
            orderedMarkerBlock(id: b),
        ])
        let visibleIndex = VisibleBlockIndex(document: document)
        let expectedMarkerKinds: [BlockMarkerKind] = [
            .orderedListItem(number: 1),
            .none,
            .orderedListItem(number: 1),
        ]

        // When
        let markerSequence = BlockMarkerSequence(
            document: document,
            visibleIndex: visibleIndex
        )

        // Then
        #expect(markerKinds(markerSequence, visibleIndex: visibleIndex) == expectedMarkerKinds)
    }

    @Test("잘못된 restart number는 1로 정규화된다")
    func invalidRestartNumberIsNormalizedToOne() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let document = makeFlatDocument([
            orderedMarkerBlock(id: a, restartNumber: 0),
            orderedMarkerBlock(id: b),
        ])
        let visibleIndex = VisibleBlockIndex(document: document)
        let expectedMarkerKinds: [BlockMarkerKind] = [
            .orderedListItem(number: 1),
            .orderedListItem(number: 2),
        ]

        // When
        let markerSequence = BlockMarkerSequence(
            document: document,
            visibleIndex: visibleIndex
        )

        // Then
        #expect(markerKinds(markerSequence, visibleIndex: visibleIndex) == expectedMarkerKinds)
    }

    @Test("visible index 기반 projection은 문서 visible order로 marker를 만든다")
    func visibleIndexProjectionBuildsMarkersFromDocumentVisibleOrder() {
        // Given
        let a: BlockID = "a"
        let child: BlockID = "child"
        let b: BlockID = "b"
        var document = makeFlatDocument([
            orderedMarkerBlock(id: a),
            orderedMarkerBlock(id: b, restartNumber: 7),
        ])
        document.appendChild(orderedMarkerBlock(id: child), to: a)
        let visibleIndex = VisibleBlockIndex(document: document)
        let expectedMarkerKinds: [BlockMarkerKind] = [
            .orderedListItem(number: 1),
            .orderedListItem(number: 1),
            .orderedListItem(number: 7),
        ]

        // When
        let indexMarkers = BlockMarkerSequence(
            document: document,
            visibleIndex: visibleIndex
        )

        // Then
        #expect(markerKinds(indexMarkers, visibleIndex: visibleIndex) == expectedMarkerKinds)
    }

    @Test("marker 조회는 비 ordered marker kind를 노출한다")
    func markerLookupExposesNonOrderedMarkerKinds() throws {
        // Given
        let unordered: BlockID = "unordered"
        let todo: BlockID = "todo"
        let document = makeFlatDocument([
            Block(id: unordered, kind: .unorderedListItem, content: BlockContent(text: "item")),
            Block(id: todo, kind: .todo(isChecked: true), content: BlockContent(text: "done")),
        ])

        // When
        let markerSequence = BlockMarkerSequence(
            document: document,
            visibleIndex: VisibleBlockIndex(document: document)
        )

        // Then
        #expect(markerSequence.markerKind(for: unordered) == .unorderedListItem)
        #expect(markerSequence.markerKind(for: todo) == .todo(isChecked: true))
    }
}
