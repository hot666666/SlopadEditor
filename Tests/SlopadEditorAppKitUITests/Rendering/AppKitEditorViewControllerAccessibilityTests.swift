import AppKit
import SlopadEditorEngine
import Testing

@testable import SlopadEditorAppKitUI

@MainActor
@Suite("AppKit editor 접근성 계약")
struct AppKitEditorViewControllerAccessibilityTests {
    @Test("canvas는 host identifier를 가진 native text area로 노출된다")
    func canvasUsesHostAccessibilityIdentity() {
        // Given
        let controller = makeController(text: "Accessible body")

        // When
        controller.configureEditorAccessibility(
            identifier: "DocumentEditor.Body",
            label: "Document body"
        )
        controller.renderAndSyncSurface(makeFirstResponder: false)

        // Then
        #expect(controller.canvasView.isAccessibilityElement())
        #expect(controller.canvasView.accessibilityRole() == .textArea)
        #expect(controller.canvasView.accessibilityIdentifier() == "DocumentEditor.Body")
        #expect(controller.canvasView.accessibilityLabel() == "Document body")
        #expect(controller.canvasView.accessibilityValue() as? String == "Accessible body")
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
        #expect(controller.canvasView.accessibilityValue() as? String == "Before!")
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
