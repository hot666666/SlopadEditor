import Testing

import SlopadCoreModel
import SlopadEditorModel

@Suite("EditorModel Enter 키 명령")
struct EditorModelEnterKeyCommandTests {
    @Test("문단 중간에서 Enter 키 명령은 블록을 나누고 새 블록으로 캐럿을 이동한다")
    func givenMiddleCaret_whenEnter_thenBlockSplitsAndCaretMoves() throws {
        // Given
        let blockID: BlockID = "block"
        let editor = EditorModel(
            document: .singleParagraph("HelloWorld", id: blockID),
            selection: .caret(blockID: blockID, offset: 5)
        )
        let expectedOriginalText = "Hello"
        let expectedCreatedText = "World"
        let expectedCreatedOffset = 0

        func createdBlockID(in change: EditorChange) -> BlockID? {
            change.operations.compactMap { operation -> BlockID? in
                if case .splitBlock(_, let created) = operation { return created }
                return nil
            }.first
        }

        // When
        let result = editor.apply(.handleEnter)

        // Then
        let change = try #require(result.outcome?.change)
        let createdID = try #require(createdBlockID(in: change))
        #expect(editor.document.blocks[blockID]?.content.text == expectedOriginalText)
        #expect(editor.document.blocks[createdID]?.content.text == expectedCreatedText)
        #expect(editor.selection == .caret(blockID: createdID, offset: expectedCreatedOffset))
    }

    @Test("빈 root list item에서 Enter 키 명령은 문단으로 변환한다")
    func givenEmptyRootListItem_whenEnter_thenBlockBecomesParagraph() throws {
        // Given
        let blockID: BlockID = "item"
        var document = Document.singleParagraph("", id: blockID)
        try document.setBlockKind(blockID: blockID, kind: .unorderedListItem).get()
        let editor = EditorModel(
            document: document, selection: .caret(blockID: blockID, offset: 0))
        let expectedKind = BlockKind.paragraph

        // When
        _ = editor.apply(.handleEnter)

        // Then
        #expect(editor.document.blocks[blockID]?.kind == expectedKind)
    }

    @Test("빈 nested todo에서 Enter 키 명령은 outdent 후 문단으로 변환한다")
    func givenEmptyNestedTodo_whenEnter_thenBlockOutdentsAndBecomesParagraph() throws {
        // Given
        let root: BlockID = "root"
        let nested: BlockID = "nested"
        var document = Document.singleParagraph("root", id: root)
        document.appendChild(Block(id: nested, kind: .todo(isChecked: false)), to: root)
        let editor = EditorModel(document: document, selection: .caret(blockID: nested, offset: 0))
        let expectedRootBlockIDs = [root, nested]
        let expectedParentID: BlockID? = nil
        let expectedKind = BlockKind.paragraph

        // When
        _ = editor.apply(.handleEnter)

        // Then
        #expect(editor.document.rootBlockIDs == expectedRootBlockIDs)
        #expect(editor.document.blocks[nested]?.parentID == expectedParentID)
        #expect(editor.document.blocks[nested]?.kind == expectedKind)
    }

    @Test("코드 블록에서 Shift-Enter 키 명령은 같은 블록 안에 줄바꿈을 삽입한다")
    func givenCodeBlockCaret_whenShiftEnter_thenNewlineIsInserted() throws {
        // Given
        let blockID: BlockID = "code"
        var document = Document.singleParagraph("ab", id: blockID)
        try document.setBlockKind(blockID: blockID, kind: .codeBlock(language: nil)).get()
        let editor = EditorModel(
            document: document, selection: .caret(blockID: blockID, offset: 1))
        let expectedText = "a\nb"

        // When
        _ = editor.apply(.handleShiftEnter)

        // Then
        let block = try #require(editor.document.blocks[blockID])
        #expect(block.content.text == expectedText)
    }
}
