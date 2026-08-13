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
        #expect(controller.scrollView.isAccessibilityEnabled())
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

    @Test("native accessibility parent와 children graph는 순환하지 않는다")
    func accessibilityGraphIsAcyclic() {
        // Given
        let controller = makeController(text: "Graph")
        controller.configureEditorAccessibility(
            identifier: "DocumentEditor.Body",
            label: "Document body"
        )
        controller.renderAndSyncSurface(makeFirstResponder: false)

        // When / Then
        var parentIDs = Set<ObjectIdentifier>()
        var parent: AnyObject? = controller.scrollView
        while let current = parent as? NSObject {
            #expect(parentIDs.insert(ObjectIdentifier(current)).inserted)
            parent = (current as? NSAccessibilityProtocol)?.accessibilityParent() as AnyObject?
        }

        assertAcyclicChildren(
            of: controller.scrollView,
            ancestors: [],
            remainingDepth: 16
        )
    }

    private func assertAcyclicChildren(
        of element: NSObject,
        ancestors: Set<ObjectIdentifier>,
        remainingDepth: Int
    ) {
        guard remainingDepth > 0 else { return }
        let identifier = ObjectIdentifier(element)
        #expect(!ancestors.contains(identifier))
        var nextAncestors = ancestors
        nextAncestors.insert(identifier)
        let children = (element as? NSAccessibilityProtocol)?.accessibilityChildren() ?? []
        for child in children {
            guard let child = child as? NSObject else { continue }
            assertAcyclicChildren(
                of: child,
                ancestors: nextAncestors,
                remainingDepth: remainingDepth - 1
            )
        }
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
