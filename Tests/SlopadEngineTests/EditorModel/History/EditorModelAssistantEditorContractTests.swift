import Testing

import SlopadCoreModel
@testable import SlopadEditorModel

@Suite("AssistantEditorContract EditorModel document replacement")
struct EditorModelAssistantEditorContractTests {
    @Test("full post-image와 selection은 한 history transaction으로 복원된다")
    func storesOneReplacementTransaction() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let before = [
            EditorBlockInput(id: a, content: BlockContent(text: "A")),
            EditorBlockInput(id: b, content: BlockContent(text: "B")),
        ]
        let after = [
            EditorBlockInput(id: b, kind: .quote, content: BlockContent(text: "changed")),
            EditorBlockInput(id: a, parentID: b, content: BlockContent(text: "A")),
        ]
        let editor = EditorModel(
            document: Document(blockInputs: before),
            selection: .caret(blockID: a, offset: 1)
        )

        // When
        let result = try editor.replaceDocument(
            with: after,
            selection: .caret(blockID: b, offset: 3)
        )
        let undo = editor.undo()
        let secondUndo = editor.undo()
        let redo = editor.redo()

        // Then
        #expect(result?.change.documentChanged == true)
        #expect(result?.change.operations.count == 1)
        #expect(undo?.documentChanged == true)
        #expect(secondUndo == nil)
        #expect(redo?.documentChanged == true)
        #expect(editor.document.editorBlockInputs == after)
        #expect(editor.selection == .caret(blockID: b, offset: 3))
    }

    @Test("invalid replacement는 canonical state와 history stack을 변경하지 않는다")
    func rollsBackInvalidReplacement() {
        // Given
        let blockID: BlockID = "block"
        let before = [EditorBlockInput(id: blockID, content: BlockContent(text: "before"))]
        let editor = EditorModel(
            document: Document(blockInputs: before),
            selection: .caret(blockID: blockID, offset: 2)
        )

        // When
        let error: EditorDocumentReplacementError?
        do {
            _ = try editor.replaceDocument(
                with: [EditorBlockInput(id: blockID, parentID: "missing")],
                selection: .caret(blockID: blockID, offset: 0)
            )
            error = nil
        } catch let replacementError {
            error = replacementError
        }

        // Then
        #expect(error == .missingParent(blockID: blockID, parentID: "missing"))
        #expect(editor.document.editorBlockInputs == before)
        #expect(editor.selection == .caret(blockID: blockID, offset: 2))
        #expect(editor.undoStack.isEmpty)
        #expect(editor.redoStack.isEmpty)
    }
}
