import Testing

import SlopadCoreModel
import SlopadEditorModel

@Suite("EditorModel 블록 move 명령")
struct EditorModelBlockMoveCommandTests {
    @Test("moveBlockSelection은 선택된 루트 블록들을 drop target 뒤로 이동한다")
    func givenRootBlockSelection_whenMoveBlockSelectionRuns_thenBlocksMoveAfterTarget() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let d: BlockID = "d"
        let editor = EditorModel(
            document: makeFlatDocument([
                Block(id: a),
                Block(id: b),
                Block(id: c),
                Block(id: d),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [b, c]))
        )

        // When
        let result = editor.apply(
            .moveBlockSelection(
                BlockSelection(blockIDs: [b, c]),
                target: BlockDropTarget(blockID: d, placement: .after)
            )
        )

        // Then
        let change = try #require(result.outcome?.change)
        #expect(editor.document.rootBlockIDs == [a, d, b, c])
        #expect(change.operations.count == 1)
        guard case let .moveBlocks(blockIDs: movedBlockIDs) =
            change.operations.first
        else {
            Issue.record("moveBlockSelection은 moveBlocks operation fact를 남겨야 한다")
            return
        }
        #expect(movedBlockIDs == [b, c])
        #expect(editor.selection == .blocks(BlockSelection(blockIDs: [b, c])))
    }

    @Test("moveBlockSelection은 선택된 블록 내부 target으로 이동하지 않는다")
    func givenDropTargetInsideSelection_whenMoveBlockSelectionRuns_thenNoOp() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let editor = EditorModel(
            document: makeFlatDocument([
                Block(id: a),
                Block(id: b),
                Block(id: c),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [b]))
        )

        // When
        let result = editor.apply(
            .moveBlockSelection(
                BlockSelection(blockIDs: [b]),
                target: BlockDropTarget(blockID: b, placement: .after)
            )
        )

        // Then
        #expect(result.isApplied == false)
        #expect(editor.document.rootBlockIDs == [a, b, c])
    }
}
