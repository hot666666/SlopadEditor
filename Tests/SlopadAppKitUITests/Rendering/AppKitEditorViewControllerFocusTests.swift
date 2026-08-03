import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit focus 계약")
struct AppKitEditorViewControllerFocusTests {
    @Test("setFocused는 반환 시점에 이미 상태가 반영된 synchronized action이다")
    func setFocusedIsSynchronized() {
        // Given
        let context = FocusContext()

        // When
        context.controller.setFocused(true)

        // Then
        #expect(context.controller.isFocused)
        #expect(context.window.firstResponder === context.controller.canvasView)

        // When
        context.controller.setFocused(false)

        // Then
        #expect(!context.controller.isFocused)
        #expect(context.window.firstResponder !== context.controller.canvasView)
    }

    @Test("onFocusChange는 실제 전이에서만 발화한다")
    func focusChangeFiresOnlyOnTransitions() {
        // Given
        let context = FocusContext()
        var observed: [Bool] = []
        context.controller.onFocusChange = { observed.append($0) }

        // When: 같은 값을 반복해 밀어넣는다.
        context.controller.setFocused(true)
        context.controller.setFocused(true)
        context.controller.setFocused(false)
        context.controller.setFocused(false)

        // Then
        #expect(observed == [true, false])
    }

    @Test("외부 요인으로 focus를 잃어도 onFocusChange가 발화한다")
    func focusChangeFiresWhenAnotherViewTakesFocus() {
        // Given: @FocusState 브리징이 한쪽 방향으로만 동작하면 안 된다.
        let context = FocusContext()
        let sibling = FocusableProbeView()
        context.window.contentView?.addSubview(sibling)
        context.controller.setFocused(true)

        var observed: [Bool] = []
        context.controller.onFocusChange = { observed.append($0) }

        // When: 호스트를 거치지 않고 다른 뷰가 focus를 가져간다.
        #expect(context.window.makeFirstResponder(sibling))

        // Then
        #expect(observed == [false])
        #expect(!context.controller.isFocused)
    }

    @Test("외부 요인으로 focus를 얻어도 onFocusChange가 발화한다")
    func focusChangeFiresWhenCanvasBecomesResponderDirectly() {
        // Given
        let context = FocusContext()
        var observed: [Bool] = []
        context.controller.onFocusChange = { observed.append($0) }

        // When: 클릭 경로가 하는 일과 같다.
        #expect(context.window.makeFirstResponder(context.controller.canvasView))

        // Then
        #expect(observed == [true])
        #expect(context.controller.isFocused)
    }

    @Test("blur는 이 에디터가 실제로 쥔 focus만 내려놓는다")
    func blurDoesNotStealFocusFromAnotherView() {
        // Given
        let context = FocusContext()
        let sibling = FocusableProbeView()
        context.window.contentView?.addSubview(sibling)
        #expect(context.window.makeFirstResponder(sibling))
        #expect(!context.controller.isFocused)

        // When: 에디터가 focus를 갖고 있지 않은데 호스트가 blur를 건다.
        context.controller.setFocused(false)

        // Then: 무관한 뷰의 focus를 뺏지 않는다.
        #expect(context.window.firstResponder === sibling)
    }

    @Test("window가 붙기 전 setFocused는 viewDidAppear에서 적용된다")
    func pendingFocusIsAppliedOnAppear() {
        // Given: 선언형 호스트는 mount 전에 binding을 평가한다.
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "A"))],
            selection: .caret(blockID: blockID, offset: 1)
        )

        // When
        controller.setFocused(true)
        #expect(!controller.isFocused)

        let window = makeWindow()
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        controller.viewDidAppear()

        // Then
        #expect(controller.isFocused)
        #expect(window.firstResponder === controller.canvasView)
    }

    @Test("focus(blockID:offset:)의 기존 동작이 유지된다")
    func blockFocusStillWorks() {
        // Given
        let context = FocusContext()

        // When
        context.controller.focus(blockID: context.blockID, offset: 0)

        // Then
        #expect(context.window.firstResponder === context.controller.canvasView)
        #expect(context.controller.isFocused)
    }
}

// MARK: - Support

@MainActor
private final class FocusContext {
    let blockID: BlockID = "block"
    let controller: AppKitEditorViewController
    let window: NSWindow

    init() {
        controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: "block", content: BlockContent(text: "Focus target"))],
            selection: .caret(blockID: "block", offset: 1)
        )
        window = makeWindow()
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
    }
}

/// A minimal sibling responder, so focus can move without involving the editor.
private final class FocusableProbeView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
private func makeWindow() -> NSWindow {
    NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
}
