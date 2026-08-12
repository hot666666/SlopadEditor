import AppKit
import SlopadEditorEngine
import Testing

@testable import SlopadEditorAppKitUI

@MainActor
@Suite("AppKit package command-state boundary")
struct AppKitCommandStateBoundaryTests {
    @Test("adapter는 Session command fact를 소비하고 typed action을 같은 owner path로 보낸다")
    func givenSelectedText_whenAdapterQueriesAndApplies_thenSurfaceUsesSessionFacts() throws {
        // Given
        let blockID: BlockID = "block"
        let selection = TextSelection(
            anchor: TextPosition(blockID: blockID, offset: 0),
            focus: TextPosition(blockID: blockID, offset: 4)
        )
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: blockID, content: .init(text: "text"))],
            selection: .text(selection)
        )
        controller.renderAndSyncSurface(makeFirstResponder: false)

        // When
        let state = controller.commandState
        let update = try #require(
            controller.perform(
                EditorCommandAction.toggleInlineStyle(.strong),
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        )

        // Then
        #expect(state.availability(for: .toggleInlineStyle(.strong)) == .available)
        #expect(update.committedDocumentRevision != nil)
        #expect(
            controller.documentSnapshot.blocks.first?.content.marks
                == [.init(kind: .strong, range: TextRange(0, 4))]
        )
        #expect(controller.snapshot?.commandState.toggleState(for: .strong) == .on)
    }

    @Test("todo adapter action은 clicked block 하나만 바꾸고 callback과 undo를 한 번씩 만든다")
    func givenTwoTodos_whenAdapterTogglesClickedBlock_thenOneTargetAndOneUndoArePreserved() throws {
        // Given
        let clicked: BlockID = "clicked"
        let other: BlockID = "other"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(id: clicked, kind: .todo(isChecked: false)),
                EditorBlockInput(id: other, kind: .todo(isChecked: false)),
            ],
            selection: .caret(blockID: other, offset: 0)
        )
        controller.renderAndSyncSurface(makeFirstResponder: false)
        var committedCallbacks = 0
        controller.onUpdate = { update in
            if update.committedDocumentRevision != nil {
                committedCallbacks += 1
            }
        }

        // When
        let update = try #require(controller.toggleTodo(blockID: clicked))

        // Then
        #expect(update.committedDocumentRevision != nil)
        #expect(controller.todoState(blockID: clicked) == .on)
        #expect(controller.todoState(blockID: other) == .off)
        #expect(committedCallbacks == 1)
        _ = try #require(
            controller.perform(
                .undo,
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        )
        #expect(controller.todoState(blockID: clicked) == .off)
        #expect(controller.todoState(blockID: other) == .off)
        #expect(committedCallbacks == 2)
    }
}
