import Testing

import SlopadCoreModel
import SlopadEditorModel

@Suite("EditorModel 블록 indent 명령")
struct EditorModelBlockIndentCommandTests {
    @Test("연속 root 블록 선택을 indentBlock하면 이전 root 블록의 자식으로 이동한다")
    func givenRootSelection_whenIndentBlockRuns_thenBlocksMoveUnderPreviousRoot() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let d: BlockID = "d"
        let document = makeFlatDocument([
            Block(id: a),
            Block(id: b),
            Block(id: c),
            Block(id: d),
        ])
        let selection = BlockSelection(blockIDs: [b, c])
        let editor = EditorModel(document: document, selection: .blocks(selection))
        let expectedRootBlockIDs = [a, d]
        let expectedAChildIDs = [b, c]
        let expectedParentID = a
        let expectedSelection = EditorSelection.blocks(selection)

        // When
        _ = editor.apply(.indentBlock(selection))

        // Then
        #expect(editor.document.rootBlockIDs == expectedRootBlockIDs)
        #expect(editor.document.blocks[a]?.childIDs == expectedAChildIDs)
        #expect(editor.document.blocks[b]?.parentID == expectedParentID)
        #expect(editor.document.blocks[c]?.parentID == expectedParentID)
        #expect(editor.selection == expectedSelection)
    }

    @Test("첫 root 블록은 indentBlock해도 이동하지 않는다")
    func givenFirstRoot_whenIndentBlockRuns_thenNoChange() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let document = makeFlatDocument([
            Block(id: a),
            Block(id: b),
        ])
        let selection = BlockSelection(blockIDs: [a])
        let editor = EditorModel(document: document, selection: .blocks(selection))

        // When
        let result = editor.apply(.indentBlock(selection))

        // Then
        #expect(result.isApplied == false)
        #expect(editor.document.rootBlockIDs == [a, b])
        #expect(editor.document.blocks[a]?.parentID == nil)
    }

    @Test("이미 직전 visible 부모의 자식인 블록은 추가 indent되지 않는다")
    func givenChildAlreadyUnderPreviousVisibleParent_whenIndentBlockRuns_thenNoChange() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        var document = makeFlatDocument([
            Block(id: a),
        ])
        document.appendChild(Block(id: b), to: a)
        let selection = BlockSelection(blockIDs: [b])
        let editor = EditorModel(document: document, selection: .blocks(selection))

        // When
        let result = editor.apply(.indentBlock(selection))

        // Then
        #expect(result.isApplied == false)
        #expect(editor.document.rootBlockIDs == [a])
        #expect(editor.document.blocks[a]?.childIDs == [b])
        #expect(editor.document.blocks[b]?.parentID == a)
    }

    @Test("같은 parent의 두 번째 sibling은 이전 sibling 아래로 한 단계 indent된다")
    func givenSecondSibling_whenIndentBlockRuns_thenMovesUnderPreviousSibling() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        var document = makeFlatDocument([
            Block(id: a),
        ])
        document.appendChild(Block(id: b), to: a)
        document.appendChild(Block(id: c), to: a)
        let selection = BlockSelection(blockIDs: [c])
        let editor = EditorModel(document: document, selection: .blocks(selection))

        // When
        _ = editor.apply(.indentBlock(selection))

        // Then
        #expect(editor.document.rootBlockIDs == [a])
        #expect(editor.document.blocks[a]?.childIDs == [b])
        #expect(editor.document.blocks[b]?.childIDs == [c])
        #expect(editor.document.blocks[c]?.parentID == b)
    }

    @Test("root 블록 indent parent는 직전 visible descendant가 아니라 같은 parent의 이전 sibling이다")
    func givenPreviousVisibleDescendant_whenIndentBlockRuns_thenUsesSameParentPreviousSibling() {
        // Given
        let a: BlockID = "a"
        let child: BlockID = "child"
        let b: BlockID = "b"
        var document = makeFlatDocument([
            Block(id: a),
            Block(id: b),
        ])
        document.appendChild(Block(id: child), to: a)
        let selection = BlockSelection(blockIDs: [b])
        let editor = EditorModel(document: document, selection: .blocks(selection))

        // When
        _ = editor.apply(.indentBlock(selection))

        // Then
        #expect(editor.document.blocks[b]?.parentID == a)
        #expect(editor.document.blocks[child]?.childIDs.isEmpty == true)
        #expect(editor.document.blocks[a]?.childIDs == [child, b])
    }
}
