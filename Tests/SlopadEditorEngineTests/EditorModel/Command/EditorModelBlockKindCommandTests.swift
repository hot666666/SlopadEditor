import SlopadCoreModel
import SlopadEditorDocumentModel
import Testing

@Suite("EditorModel 블록 kind 명령")
struct EditorModelBlockKindCommandTests {
    @Test("setBlockKind는 대상 블록의 kind만 변경한다")
    func givenParagraph_whenSetBlockKindRuns_thenTargetKindChanges() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "B")),
        ])
        let editor = EditorModel(document: document, selection: .caret(blockID: a, offset: 0))
        let expectedAKind = BlockKind.heading(level: .h2)
        let expectedBKind = BlockKind.paragraph

        // When
        _ = editor.apply(.setBlockKind(blockID: a, kind: .heading(level: .h2)))

        // Then
        #expect(editor.document.blocks[a]?.kind == expectedAKind)
        #expect(editor.document.blocks[b]?.kind == expectedBKind)
    }

    @Test("todo 블록을 toggleTodo하면 checked 상태가 반전된다")
    func givenCheckedTodo_whenToggleTodoRuns_thenTodoBecomesUnchecked() throws {
        // Given
        let blockID: BlockID = "todo"
        var document = Document.singleParagraph("Task", id: blockID)
        try document.setBlockKind(blockID: blockID, kind: .todo(isChecked: true)).get()
        let editor = EditorModel(
            document: document, selection: .caret(blockID: blockID, offset: 0))
        let expectedKind = BlockKind.todo(isChecked: false)

        // When
        _ = editor.apply(.toggleTodo(blockID: blockID))

        // Then
        #expect(editor.document.blocks[blockID]?.kind == expectedKind)
    }

    @Test("todo가 아닌 블록의 toggleTodo는 적용되지 않는다")
    func givenParagraph_whenToggleTodoRuns_thenCommandIsNotApplicable() {
        // Given
        let blockID: BlockID = "paragraph"
        let editor = EditorModel(
            document: .singleParagraph("Task", id: blockID),
            selection: .caret(blockID: blockID, offset: 0)
        )

        // When
        let result = editor.apply(.toggleTodo(blockID: blockID))

        // Then
        #expect(!result.isApplied)
        #expect(editor.document.blocks[blockID]?.kind == .paragraph)
    }
}
