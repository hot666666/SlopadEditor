import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 structural 증분 레이아웃")
struct EditorSessionIncrementalStructuralLayoutTests {
    @Test("블록 삭제는 전체 재배치 없이 height index에서 제거한다")
    func deleteUsesIncrementalLayout() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let textLayouter = RecordingBlockTextLayouter()
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "B")),
                Block(id: c, content: BlockContent(text: "C")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [b])),
            textLayouter: textLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()

        // When
        let update = session.handleCommand(.deleteBlockSelection)
        let snapshot = session.render(in: viewport)

        // Then
        #expect(update.invalidation.visibleSequenceChanged)
        #expect(snapshot.visibleBlocks.map(\.id) == [a, c])
        #expect(textLayouter.measuredBlockIDs.isEmpty)
    }

    @Test("블록 reorder는 전체 재배치 없이 height index 순서만 갱신한다")
    func moveUsesIncrementalLayout() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let d: BlockID = "d"
        let textLayouter = RecordingBlockTextLayouter()
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "B")),
                Block(id: c, content: BlockContent(text: "C")),
                Block(id: d, content: BlockContent(text: "D")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [b, c])),
            textLayouter: textLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()

        // When
        let update = session.handleCommand(
            .moveBlockSelection(
                BlockSelection(blockIDs: [b, c]),
                target: BlockDropTarget(blockID: d, placement: .after)
            )
        )
        let snapshot = session.render(in: viewport)

        // Then
        #expect(update.invalidation.visibleSequenceChanged)
        #expect(snapshot.visibleBlocks.map(\.id) == [a, d, b, c])
        #expect(textLayouter.measuredBlockIDs.isEmpty)
    }

    @Test("블록 indent는 이동한 subtree만 새 depth로 다시 측정한다")
    func indentUsesIncrementalLayout() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let textLayouter = RecordingBlockTextLayouter()
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "B")),
                Block(id: c, content: BlockContent(text: "C")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [b])),
            textLayouter: textLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()

        // When
        let update = session.handleCommand(.indentBlock(BlockSelection(blockIDs: [b])))
        let snapshot = session.render(in: viewport)

        // Then
        #expect(update.invalidation.visibleSequenceChanged)
        #expect(snapshot.visibleBlocks.map(\.id) == [a, b, c])
        #expect(snapshot.visibleBlocks.map(\.depth) == [0, 1, 0])
        #expect(textLayouter.measuredBlockIDs == [b])
    }

    @Test("블록 outdent는 이동한 subtree만 새 depth로 다시 측정한다")
    func outdentUsesIncrementalLayout() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        var document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: c, content: BlockContent(text: "C")),
        ])
        document.appendChild(Block(id: b, content: BlockContent(text: "B")), to: a)
        let textLayouter = RecordingBlockTextLayouter()
        let session = EditorSession(
            document: document,
            selection: .blocks(BlockSelection(blockIDs: [b])),
            textLayouter: textLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()

        // When
        let update = session.handleCommand(.outdentBlock(BlockSelection(blockIDs: [b])))
        let snapshot = session.render(in: viewport)

        // Then
        #expect(update.invalidation.visibleSequenceChanged)
        #expect(snapshot.visibleBlocks.map(\.id) == [a, b, c])
        #expect(snapshot.visibleBlocks.map(\.depth) == [0, 0, 0])
        #expect(textLayouter.measuredBlockIDs == [b])
    }
}
