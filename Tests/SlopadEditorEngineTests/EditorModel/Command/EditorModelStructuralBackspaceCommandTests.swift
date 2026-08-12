import Testing

import SlopadCoreModel
import SlopadEditorDocumentModel

@Suite("EditorModel structural Backspace 키 명령")
struct EditorModelStructuralBackspaceCommandTests {
    @Test("블록 선택에서 Backspace 키 명령은 선택 블록을 삭제한다")
    func givenBlockSelection_whenBackspace_thenSelectedBlocksAreRemoved() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([Block(id: a), Block(id: b), Block(id: c)])
        let editor = EditorModel(
            document: document, selection: .blocks(BlockSelection(blockIDs: [b])))
        let expectedRootBlockIDs = [a, c]

        // When
        _ = editor.apply(.handleBackspace)

        // Then
        #expect(editor.document.rootBlockIDs == expectedRootBlockIDs)
        #expect(editor.document.blocks[b] == nil)
    }

    @Test("문서 시작 위치의 Backspace 키 명령은 문서를 바꾸지 않는다")
    func givenDocumentStart_whenBackspace_thenCommandDoesNotChangeDocument() {
        // Given
        let blockID: BlockID = "a"
        let editor = EditorModel(
            document: .singleParagraph("A", id: blockID),
            selection: .caret(blockID: blockID, offset: 0)
        )
        let expectedText = "A"

        // When
        let result = editor.apply(.handleBackspace)

        // Then
        #expect(result.isApplied == false)
        #expect(editor.document.blocks[blockID]?.content.text == expectedText)
    }

    @Test("첫 번째 자식 문단에서 Backspace 키 명령은 root로 outdent한다")
    func givenFirstChildParagraph_whenBackspace_thenBlockOutdents() {
        // Given
        let root: BlockID = "root"
        let child: BlockID = "child"
        var document = Document.singleParagraph("root", id: root)
        document.appendChild(Block(id: child, content: BlockContent(text: "child")), to: root)
        let editor = EditorModel(document: document, selection: .caret(blockID: child, offset: 0))
        let expectedRootBlockIDs = [root, child]
        let expectedParentID: BlockID? = nil

        // When
        _ = editor.apply(.handleBackspace)

        // Then
        #expect(editor.document.rootBlockIDs == expectedRootBlockIDs)
        #expect(editor.document.blocks[child]?.parentID == expectedParentID)
    }

    @Test("이전 블록이 있는 root list item의 Backspace 키 명령은 문단으로 변환하고 병합하지 않는다")
    func givenRootListItemWithPreviousBlock_whenBackspace_thenBlockBecomesParagraph() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        var document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, kind: .unorderedListItem, content: BlockContent(text: "B")),
        ])
        try document.setBlockKind(blockID: b, kind: .unorderedListItem).get()
        let editor = EditorModel(document: document, selection: .caret(blockID: b, offset: 0))
        let expectedAKind = BlockKind.paragraph
        let expectedBKind = BlockKind.paragraph
        let expectedAText = "A"
        let expectedBText = "B"
        let expectedRootBlockIDs = [a, b]

        // When
        _ = editor.apply(.handleBackspace)

        // Then
        #expect(editor.document.blocks[a]?.kind == expectedAKind)
        #expect(editor.document.blocks[b]?.kind == expectedBKind)
        #expect(editor.document.blocks[a]?.content.text == expectedAText)
        #expect(editor.document.blocks[b]?.content.text == expectedBText)
        #expect(editor.document.rootBlockIDs == expectedRootBlockIDs)
    }

    @Test("이전 블록이 있는 heading 시작 위치의 Backspace 키 명령은 문단으로 변환하고 병합하지 않는다")
    func givenHeadingWithPreviousBlock_whenBackspace_thenBlockBecomesParagraph() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        var document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "B")),
        ])
        try document.setBlockKind(blockID: b, kind: .heading(level: .h1)).get()
        let editor = EditorModel(document: document, selection: .caret(blockID: b, offset: 0))
        let expectedAKind = BlockKind.paragraph
        let expectedBKind = BlockKind.paragraph
        let expectedAText = "A"
        let expectedBText = "B"
        let expectedRootBlockIDs = [a, b]

        // When
        _ = editor.apply(.handleBackspace)

        // Then
        #expect(editor.document.blocks[a]?.kind == expectedAKind)
        #expect(editor.document.blocks[b]?.kind == expectedBKind)
        #expect(editor.document.blocks[a]?.content.text == expectedAText)
        #expect(editor.document.blocks[b]?.content.text == expectedBText)
        #expect(editor.document.rootBlockIDs == expectedRootBlockIDs)
    }

    @Test("이전 블록이 있는 문단 시작 위치의 Backspace 키 명령은 이전 블록에 병합한다")
    func givenParagraphWithPreviousBlock_whenBackspace_thenBlocksMerge() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "B")),
        ])
        let editor = EditorModel(document: document, selection: .caret(blockID: b, offset: 0))
        let expectedRootBlockIDs = [a]
        let expectedMergedText = "AB"
        let expectedSelection = EditorSelection.caret(blockID: a, offset: 1)

        // When
        _ = editor.apply(.handleBackspace)

        // Then
        #expect(editor.document.rootBlockIDs == expectedRootBlockIDs)
        #expect(editor.document.blocks[a]?.content.text == expectedMergedText)
        #expect(editor.document.blocks[b] == nil)
        #expect(editor.selection == expectedSelection)
    }

    @Test("같은 깊이의 list 형제에서 두 번째 시작 Backspace 키 명령은 문단으로 변환하고 병합하지 않는다")
    func givenListSibling_whenBackspace_thenBlockBecomesParagraph() {
        // Given
        let root: BlockID = "root"
        let a: BlockID = "a"
        let b: BlockID = "b"
        var document = Document.singleParagraph("root", id: root)
        document.appendChild(
            Block(id: a, kind: .unorderedListItem, content: BlockContent(text: "A")), to: root)
        document.appendChild(
            Block(id: b, kind: .unorderedListItem, content: BlockContent(text: "B")), to: root)
        let editor = EditorModel(document: document, selection: .caret(blockID: b, offset: 0))
        let expectedRootChildIDs = [a, b]
        let expectedAText = "A"
        let expectedBText = "B"
        let expectedBKind = BlockKind.paragraph

        // When
        _ = editor.apply(.handleBackspace)

        // Then
        #expect(editor.document.blocks[root]?.childIDs == expectedRootChildIDs)
        #expect(editor.document.blocks[a]?.content.text == expectedAText)
        #expect(editor.document.blocks[b]?.content.text == expectedBText)
        #expect(editor.document.blocks[b]?.kind == expectedBKind)
    }
}
