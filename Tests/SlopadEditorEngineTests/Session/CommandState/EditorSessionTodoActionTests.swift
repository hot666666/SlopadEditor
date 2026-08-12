import SlopadEditorCoreModel
import Testing

@testable import SlopadEditorEngine

@Suite("EditorSession per-block todo action")
struct EditorSessionTodoActionTests {
    @Test("todoState와 toggleTodo는 지정한 todo 한 개만 한 transaction으로 바꾼다")
    func givenTwoTodos_whenTogglingOne_thenOnlyClickedBlockChangesAndUndoRestoresIt() throws {
        // Given
        let clicked: BlockID = "clicked"
        let other: BlockID = "other"
        let session = makeSession(blocks: [
            EditorBlockInput(id: clicked, kind: .todo(isChecked: false)),
            EditorBlockInput(id: other, kind: .todo(isChecked: true)),
        ])

        // When
        let before = session.todoState(blockID: clicked)
        let update = try #require(session.toggleTodo(blockID: clicked))

        // Then
        #expect(before == .off)
        #expect(update.committedDocumentRevision != nil)
        #expect(session.todoState(blockID: clicked) == .on)
        #expect(session.todoState(blockID: other) == .on)
        _ = try #require(session.handleInput(.command(.undo)))
        #expect(session.todoState(blockID: clicked) == .off)
        #expect(session.todoState(blockID: other) == .on)
    }

    @Test("missing과 non-todo 대상은 unavailable이며 toggleTodo가 문서나 history를 바꾸지 않는다")
    func givenInvalidTodoTargets_whenToggling_thenActionIsNoOp() {
        // Given
        let paragraph: BlockID = "paragraph"
        let session = makeSession(blocks: [EditorBlockInput(id: paragraph)])
        let before = session.documentSnapshot

        // When
        let paragraphUpdate = session.toggleTodo(blockID: paragraph)
        let missingUpdate = session.toggleTodo(blockID: "missing")

        // Then
        #expect(session.todoState(blockID: paragraph) == .unavailable)
        #expect(session.todoState(blockID: "missing") == .unavailable)
        #expect(paragraphUpdate == nil)
        #expect(missingUpdate == nil)
        #expect(session.documentSnapshot.blocks == before.blocks)
        #expect(session.handleInput(.command(.undo)) == nil)
    }

    @Test("todo query 뒤 kind가 바뀌면 apply가 existence와 kind를 다시 검증한다")
    func givenStaleTodoFact_whenKindChangesBeforeApply_thenToggleIsRejected() throws {
        // Given
        let blockID: BlockID = "todo"
        let session = makeSession(blocks: [
            EditorBlockInput(id: blockID, kind: .todo(isChecked: false))
        ])
        #expect(session.todoState(blockID: blockID) == .off)
        let modelResult = session.editorModel.apply(
            .setBlockKind(blockID: blockID, kind: .paragraph)
        )
        _ = try #require(modelResult.outcome)

        // When
        let update = session.toggleTodo(blockID: blockID)

        // Then
        #expect(update == nil)
        #expect(session.todoState(blockID: blockID) == .unavailable)
        #expect(session.editorModel.document.block(blockID)?.kind == .paragraph)
    }

    private func makeSession(blocks: [EditorBlockInput]) -> EditorSession {
        let first = blocks[0].id
        return EditorSession(
            blocks: blocks,
            selection: .caret(blockID: first, offset: 0),
            textLayouter: DeterministicBlockTextLayouter()
        )
    }
}
