import AppKit
import SlopadEditorEngine
import Testing

@testable import SlopadEditorAppKitUI

@MainActor
@Suite("AppKit editor 접근성 계약")
struct AppKitEditorViewControllerAccessibilityTests {
    @Test("native scroll surface는 AppKit role을 보존하고 host identity를 가진다")
    func scrollSurfaceUsesHostAccessibilityIdentity() {
        // Given
        let controller = makeController(text: "Accessible body")

        // When
        controller.configureEditorAccessibility(
            identifier: "DocumentEditor.Body",
            label: "Document body"
        )
        controller.renderAndSyncSurface(makeFirstResponder: false)

        // Then
        #expect(controller.scrollView.accessibilityRole() == .scrollArea)
        #expect(controller.scrollView.accessibilityIdentifier() == "DocumentEditor.Body")
        #expect(controller.scrollView.accessibilityLabel() == "Document body")
        #expect(controller.scrollView.accessibilityValue() as? String == "Accessible body")
        #expect(!controller.canvasView.isAccessibilityElement())
    }

    @Test("canonical edit 뒤 accessibility value가 최신 plain text로 갱신된다")
    func accessibilityValueTracksCanonicalEdits() {
        // Given
        let controller = makeController(text: "Before")
        controller.renderAndSyncSurface(makeFirstResponder: false)

        // When
        controller.perform(
            .insertText("!"),
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )

        // Then
        #expect(controller.scrollView.accessibilityValue() as? String == "Before!")
    }

    private func makeController(text: String) -> AppKitEditorViewController {
        AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: "block",
                    content: BlockContent(text: text)
                )
            ],
            selection: .caret(blockID: "block", offset: text.count)
        )
    }
}
