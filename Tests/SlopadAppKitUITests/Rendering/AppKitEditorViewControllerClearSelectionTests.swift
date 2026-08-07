import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit clearSelection 계약")
struct AppKitEditorViewControllerClearSelectionTests {
    @Test("clearSelection은 선택 모드와 무관하게 한 번에 해제한다")
    func clearsAnySelectionInOneAction() throws {
        // Given: escape 두 번으로 흉내내면 시작 모드마다 필요한 횟수가 달라진다.
        let context = ClearSelectionContext()

        // When: caret에서 바로 해제한다.
        let fromCaret = try #require(
            context.controller.perform(
                .clearSelection,
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        )

        // Then
        #expect(fromCaret.selection == .inactive)

        // When: 블록 선택에서도 마찬가지다.
        context.controller.perform(
            .escape,
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )
        context.controller.focus(blockID: context.blockID, offset: 1)
        context.controller.perform(
            .escape,
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )
        let fromBlocks = try #require(
            context.controller.perform(
                .clearSelection,
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        )

        // Then
        #expect(fromBlocks.selection == .inactive)
    }

    @Test("clearSelection은 responder를 가져오지 않는다")
    func clearingSelectionDoesNotTakeTheResponder() {
        // Given: 바깥 클릭으로 선택을 지우는 호스트가 focus를 되뺏으면 안 된다.
        let context = ClearSelectionContext()
        let sibling = FocusableProbeView()
        context.window.contentView?.addSubview(sibling)
        #expect(context.window.makeFirstResponder(sibling))

        // When
        context.controller.perform(
            .clearSelection,
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )

        // Then
        #expect(context.window.firstResponder === sibling)
        #expect(!context.controller.isFocused)
    }

    @Test("이미 해제된 상태의 clearSelection은 호스트로 넘어간다")
    func refusedClearSelectionReachesTheHost() {
        // Given
        let context = ClearSelectionContext()
        var observed: [AppKitEditorAction] = []
        context.controller.onUnhandledAction = { action in
            observed.append(action)
            return false
        }

        // When
        for _ in 0..<2 {
            context.controller.perform(
                .clearSelection,
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        }

        // Then: 첫 번째는 engine이 소비하고, 두 번째만 escalate된다.
        #expect(observed == [.clearSelection])
    }
}

// MARK: - Support

@MainActor
private final class ClearSelectionContext {
    let blockID: BlockID = "block"
    let controller: AppKitEditorViewController
    let window: NSWindow

    init() {
        controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: "block", content: BlockContent(text: "Selected"))],
            selection: .caret(blockID: "block", offset: 1)
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
    }
}

/// A minimal sibling responder, so focus can sit outside the editor.
private final class FocusableProbeView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
