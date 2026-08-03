import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit canonical document snapshot")
struct AppKitEditorViewControllerDocumentSnapshotTests {
    @Test("committed update callback은 같은 revision의 full snapshot을 동기 조회한다")
    func readsMatchingSnapshotDuringUpdateCallback() throws {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "A")
                )
            ],
            selection: .caret(blockID: blockID, offset: 1)
        )
        var deliveredSnapshot: EditorDocumentSnapshot?
        controller.onUpdate = { [weak controller] update in
            guard let revision = update.committedDocumentRevision else { return }
            guard let controller else { return }
            let snapshot = controller.documentSnapshot
            #expect(snapshot.revision == revision)
            deliveredSnapshot = snapshot
        }

        // When
        let update = try #require(
            controller.perform(
                .insertText("!"),
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        )

        // Then
        #expect(update.committedDocumentRevision?.rawValue == 1)
        #expect(deliveredSnapshot?.revision == update.committedDocumentRevision)
        #expect(deliveredSnapshot?.blocks.map(\.id) == [blockID])
        #expect(deliveredSnapshot?.blocks.first?.content.text == "A!")
    }
}
