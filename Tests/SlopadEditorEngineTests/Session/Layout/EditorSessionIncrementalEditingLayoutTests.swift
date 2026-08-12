import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 editing 증분 레이아웃")
struct EditorSessionIncrementalEditingLayoutTests {
    @Test("블록 split은 전체 재배치 없이 원본과 생성 블록만 측정한다")
    func splitUsesIncrementalLayout() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let textLayouter = RecordingBlockTextLayouter()
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "AB")),
                Block(id: b, content: BlockContent(text: "B")),
                Block(id: c, content: BlockContent(text: "C")),
            ]),
            textLayouter: textLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()

        // When
        let update = session.handleCommand(.splitBlock(blockID: a, offset: 1))
        let snapshot = session.render(in: viewport)
        let measured = textLayouter.measuredBlockIDs

        // Then
        #expect(update.invalidation.visibleSequenceChanged)
        #expect(snapshot.visibleBlocks.map(\.id).contains(a))
        #expect(measured.contains(a))
        #expect(!measured.contains(b))
        #expect(!measured.contains(c))
        #expect(measured.count == 2)
    }

    @Test("블록 merge는 전체 재배치 없이 target 블록만 다시 측정한다")
    func mergeUsesIncrementalLayout() {
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
            textLayouter: textLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()

        // When
        let update = session.handleCommand(.mergeBlocks(target: a, source: b))
        let snapshot = session.render(in: viewport)

        // Then
        #expect(update.invalidation.visibleSequenceChanged)
        #expect(snapshot.visibleBlocks.map(\.id) == [a, c])
        #expect(textLayouter.measuredBlockIDs == [a])
    }

    @Test("자식이 있는 블록 split은 transferred child의 visible depth를 새 구조에 맞춘다")
    func splitWithChildUpdatesVisibleDepthIncrementally() throws {
        // Given
        let parent: BlockID = "parent"
        let child: BlockID = "child"
        var document = Document.singleParagraph("AB", id: parent)
        document.appendChild(Block(id: child, content: BlockContent(text: "child")), to: parent)
        let textLayouter = RecordingBlockTextLayouter()
        let session = EditorSession(document: document, textLayouter: textLayouter)
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()

        // When
        _ = session.handleCommand(.splitBlock(blockID: parent, offset: 1))
        let createdID = try #require(session.document.rootBlockIDs.first { $0 != parent })
        let snapshot = session.render(in: viewport)

        // Then
        #expect(snapshot.visibleBlocks.map(\.id) == [parent, createdID, child])
        #expect(snapshot.visibleBlocks.map(\.depth) == [0, 0, 1])
        #expect(textLayouter.measuredBlockIDs.count == 2)
    }
}
