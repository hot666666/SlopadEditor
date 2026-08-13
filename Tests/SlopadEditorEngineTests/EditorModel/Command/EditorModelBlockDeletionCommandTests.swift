import Testing

import SlopadEditorCoreModel
import SlopadEditorDocumentModel

@Suite("EditorModel 블록 삭제 명령")
struct EditorModelBlockDeletionCommandTests {
    @Test("선택된 블록 삭제는 visible tree에서 해당 블록을 제거한다")
    func givenSelectedBlock_whenDeleteBlockSelectionRuns_thenBlockIsRemovedFromVisibleTree() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([Block(id: a), Block(id: b), Block(id: c)])
        let editor = EditorModel(
            document: document, selection: .blocks(BlockSelection(blockIDs: [b])))
        let expectedRootBlockIDs = [a, c]

        // When
        _ = editor.apply(.deleteBlockSelection)

        // Then
        #expect(editor.document.rootBlockIDs == expectedRootBlockIDs)
        #expect(editor.document.blocks[b] == nil)
    }
}
