import Testing

import SlopadEditorCoreModel
import SlopadEditorDocumentModel

@Suite("EditorModel 블록 outdent 명령")
struct EditorModelBlockOutdentCommandTests {
    @Test("연속 sibling 블록 선택을 outdentBlock하면 parent 다음 root 순서로 이동한다")
    func givenSiblingSelection_whenOutdentBlockRuns_thenBlocksMoveAfterParent() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let d: BlockID = "d"
        var document = makeFlatDocument([
            Block(id: a),
            Block(id: d),
        ])
        document.appendChild(Block(id: b), to: a)
        document.appendChild(Block(id: c), to: a)
        let selection = BlockSelection(blockIDs: [b, c])
        let editor = EditorModel(document: document, selection: .blocks(selection))
        let expectedRootBlockIDs = [a, b, c, d]
        let expectedAChildIDs: [BlockID] = []
        let expectedParentID: BlockID? = nil
        let expectedSelection = EditorSelection.blocks(selection)

        // When
        _ = editor.apply(.outdentBlock(selection))

        // Then
        #expect(editor.document.rootBlockIDs == expectedRootBlockIDs)
        #expect(editor.document.blocks[a]?.childIDs == expectedAChildIDs)
        #expect(editor.document.blocks[b]?.parentID == expectedParentID)
        #expect(editor.document.blocks[c]?.parentID == expectedParentID)
        #expect(editor.selection == expectedSelection)
    }
}
