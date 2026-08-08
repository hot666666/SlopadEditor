import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit native mouse text selection")
struct AppKitEditorViewControllerMouseTextSelectionTests {
    @Test("mouse down drag up 경로가 responder와 text selection을 동기화한다")
    func nativeMouseDragProducesTextSelection() throws {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: String(repeating: "selection ", count: 30))
                )
            ],
            selection: .caret(blockID: blockID, offset: 0),
            focusOnAppear: false
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 240)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let frame = try #require(
            controller.session.blockRevealFrame(
                for: blockID,
                viewport: controller.currentViewport()
            )
        )
        let textOriginX =
            controller.editorStyle.gutterWidth
            + controller.editorStyle.contentHorizontalPadding
        let start = CGPoint(x: textOriginX + 8, y: frame.y + frame.height * 0.5)
        let end = CGPoint(x: textOriginX + 220, y: start.y)

        // When
        controller.handleMouseDown(documentPoint: start, clickCount: 1)
        for step in 1...4 {
            let progress = Double(step) / 4
            controller.handleMouseDragged(
                documentPoint: CGPoint(
                    x: start.x + (end.x - start.x) * CGFloat(progress),
                    y: start.y
                )
            )
        }
        controller.handleMouseUp(documentPoint: end)

        // Then
        #expect(window.firstResponder === controller.canvasView)
        guard case .text(let selection) = controller.snapshot?.selection else {
            Issue.record("native mouse drag가 text selection을 남기지 않음")
            return
        }
        #expect(selection.isSingleBlock)
        #expect(selection.anchor.offset != selection.focus.offset)
    }
}
