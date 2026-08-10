import SlopadCoreModel
import Testing

@testable import SlopadEditorModel

@Suite("EditorModel canonical text span order cache")
struct EditorModelResolvedTextSpanTests {
    @Test("content와 style 변경은 canonical order cache를 재구축하지 않는다")
    func givenResolvedTN_whenContentOnlyEditsRun_thenStructuralOrderCacheIsReused() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let selection = TextSelection(
            anchor: TextPosition(blockID: a, offset: 0),
            focus: TextPosition(blockID: c, offset: 1)
        )
        let editor = EditorModel(
            document: makeFlatDocument([
                Block(id: a, content: .init(text: "A")),
                Block(id: b, content: .init(text: "B")),
                Block(id: c, content: .init(text: "C")),
            ]),
            selection: .text(selection)
        )
        #expect(try #require(editor.resolveTextSpan(selection)).blockIDs == [a, b, c])
        let initialRebuildCount = editor.canonicalBlockOrderRebuildCount

        // When
        _ = editor.apply(.replaceText(blockID: b, range: .point(1), text: "!"))
        _ = editor.apply(.applyTextStyle(blockID: a, range: TextRange(0, 1), style: .strong))
        let resolvedAfterContentEdits = try #require(editor.resolveTextSpan(selection))

        // Then
        #expect(resolvedAfterContentEdits.blockIDs == [a, b, c])
        #expect(editor.canonicalBlockOrderRebuildCount == initialRebuildCount)
    }

    @Test("structural move와 undo redo는 order generation을 갱신하고 새 DFS 순서를 만든다")
    func givenResolvedTN_whenStructureMovesAndHistoryRuns_thenOrderRebuildsCorrectly() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let originalSelection = TextSelection(
            anchor: TextPosition(blockID: a, offset: 0),
            focus: TextPosition(blockID: c, offset: 1)
        )
        let movedSelection = TextSelection(
            anchor: TextPosition(blockID: c, offset: 0),
            focus: TextPosition(blockID: b, offset: 1)
        )
        let editor = EditorModel(
            document: makeFlatDocument([
                Block(id: a, content: .init(text: "A")),
                Block(id: b, content: .init(text: "B")),
                Block(id: c, content: .init(text: "C")),
            ]),
            selection: .text(originalSelection)
        )
        _ = try #require(editor.resolveTextSpan(originalSelection))
        let initialRebuildCount = editor.canonicalBlockOrderRebuildCount

        // When
        _ = editor.apply(
            .moveBlockSelection(
                BlockSelection(blockIDs: [c]),
                target: BlockDropTarget(blockID: a, placement: .before)
            )
        )
        let moved = try #require(editor.resolveTextSpan(movedSelection))
        _ = try #require(editor.undo())
        let undone = try #require(editor.resolveTextSpan(originalSelection))
        _ = try #require(editor.redo())
        let redone = try #require(editor.resolveTextSpan(movedSelection))

        // Then
        #expect(moved.blockIDs == [c, a, b])
        #expect(undone.blockIDs == [a, b, c])
        #expect(redone.blockIDs == [c, a, b])
        #expect(editor.canonicalBlockOrderRebuildCount == initialRebuildCount + 3)
    }
}
