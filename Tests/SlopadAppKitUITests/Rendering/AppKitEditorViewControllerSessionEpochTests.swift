import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit 세션 epoch")
struct AppKitEditorViewControllerSessionEpochTests {
    @Test("resetDocument는 revision을 되감고 epoch을 바꾼다")
    func resetDocumentRewindsRevisionAndChangesEpoch() throws {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "A"))],
            selection: .caret(blockID: blockID, offset: 1)
        )
        _ = try #require(
            controller.perform(
                .insertText("!"),
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        )
        let captured = controller.documentSnapshot
        #expect(captured.revision.rawValue == 1)

        // When
        controller.resetDocument(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "B"))],
            selection: .caret(blockID: blockID, offset: 1)
        )
        _ = try #require(
            controller.perform(
                .insertText("?"),
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        )
        let current = controller.documentSnapshot

        // Then: 두 스냅샷의 revision이 같으므로 revision만 든 호스트는 교체를 놓친다.
        #expect(captured.revision == current.revision)
        #expect(captured.epoch != current.epoch)
    }

    @Test("문서 교체 없이 편집만 하면 epoch이 유지된다")
    func editingKeepsTheEpoch() throws {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "A"))],
            selection: .caret(blockID: blockID, offset: 1)
        )
        let initial = controller.documentSnapshot.epoch

        // When
        for text in ["1", "2", "3"] {
            _ = try #require(
                controller.perform(
                    .insertText(text),
                    makeFirstResponder: false,
                    scrollSelectionIntoView: false
                )
            )
        }

        // Then
        #expect(controller.documentSnapshot.epoch == initial)
        #expect(controller.documentSnapshot.revision.rawValue == 3)
    }

    @Test("update 콜백의 epoch으로 호스트가 staleness를 값 비교로 판정한다")
    func hostDecidesStalenessFromCallbackValues() throws {
        // Given: 호스트가 committed change token을 잡아둔다.
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "A"))],
            selection: .caret(blockID: blockID, offset: 1)
        )
        var pendingToken: (epoch: EditorSessionEpoch, revision: EditorDocumentRevision)?
        controller.onUpdate = { update in
            guard let revision = update.committedDocumentRevision else { return }
            pendingToken = (update.epoch, revision)
        }
        _ = try #require(
            controller.perform(
                .insertText("!"),
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        )
        let token = try #require(pendingToken)

        // When: 영속화가 일어나기 전에 문서가 교체된다.
        controller.resetDocument(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "B"))],
            selection: .caret(blockID: blockID, offset: 1)
        )

        // Then: 호스트 쪽 generation counter 없이 public 값만으로 stale임을 안다.
        #expect(token.epoch != controller.documentSnapshot.epoch)
    }
}
