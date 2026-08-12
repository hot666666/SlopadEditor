import Testing

import SlopadEngine
@testable import SlopadEditorAppKitUI

@MainActor
@Suite("AppKit 미소비 action 통지")
struct AppKitEditorViewControllerUnhandledActionTests {
    @Test("escape는 engine이 escalate를 끝낸 뒤에만 호스트로 넘어간다")
    func escapeReachesTheHostOnlyAtTheEndOfTheEscalation() {
        // Given: caret → blocks → inactive 를 거친 뒤에야 engine이 소비를 멈춘다.
        let controller = makeController()
        var observed: [AppKitEditorAction] = []
        controller.onUnhandledAction = { action in
            observed.append(action)
            return true
        }

        // When / Then: caret에서의 escape는 engine이 소비한다.
        controller.perform(.escape, makeFirstResponder: false, scrollSelectionIntoView: false)
        #expect(observed.isEmpty)

        // blocks에서의 escape도 engine이 소비한다.
        controller.perform(.escape, makeFirstResponder: false, scrollSelectionIntoView: false)
        #expect(observed.isEmpty)

        // inactive에서는 더 이상 할 일이 없다.
        controller.perform(.escape, makeFirstResponder: false, scrollSelectionIntoView: false)
        #expect(observed == [.escape])
    }

    @Test("escape 전용 특례가 아니다 — 다른 action도 같은 모양으로 통지된다")
    func otherRefusedActionsReportTheSameWay() {
        // Given: 되돌릴 것이 없는 상태의 undo/redo, 선택이 없는 상태의 cut.
        let controller = makeController()
        var observed: [AppKitEditorAction] = []
        controller.onUnhandledAction = { action in
            observed.append(action)
            return true
        }

        // When
        for action in [AppKitEditorAction.undo, .redo, .cutSelection] {
            controller.perform(action, makeFirstResponder: false, scrollSelectionIntoView: false)
        }

        // Then
        #expect(observed == [.undo, .redo, .cutSelection])
    }

    @Test("engine이 소비한 action은 반환값과 무관하게 통지되지 않는다")
    func consumedActionsAreNeverReported() {
        // Given
        let controller = makeController()
        var observed: [AppKitEditorAction] = []
        controller.onUnhandledAction = { action in
            observed.append(action)
            return false
        }

        // When
        let update = controller.perform(
            .insertText("x"),
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )

        // Then
        #expect(update != nil)
        #expect(observed.isEmpty)
    }

    @Test("콜백을 달지 않으면 기존 동작이 그대로다")
    func absentCallbackChangesNothing() {
        // Given
        let controller = makeController()

        // When: inactive까지 밀어낸 뒤 한 번 더 escape.
        for _ in 0..<3 {
            controller.perform(.escape, makeFirstResponder: false, scrollSelectionIntoView: false)
        }
        let update = controller.perform(
            .escape,
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )

        // Then: 아무 일도 일어나지 않고 nil이 그대로 반환된다.
        #expect(update == nil)
    }

    @Test("콜백 안에서 재진입해도 무한 루프가 되지 않는다")
    func reentrantCallbackTerminates() {
        // Given: 호스트가 콜백 안에서 또 거절당할 action을 수행한다.
        let controller = makeController()
        var callCount = 0
        controller.onUnhandledAction = { [weak controller] _ in
            callCount += 1
            controller?.perform(
                .escape,
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
            return true
        }

        // When
        for _ in 0..<3 {
            controller.perform(.escape, makeFirstResponder: false, scrollSelectionIntoView: false)
        }

        // Then: 재진입 통지는 삼켜지고, 바깥 호출 한 번만 관측된다.
        #expect(callCount == 1)
    }

    @Test("콜백 반환값이 native command의 처리 여부를 결정한다")
    func callbackResultDecidesNativeHandling() {
        // Given: Escape 키가 실제로 도착하는 경로.
        let controller = makeController()
        for _ in 0..<3 {
            controller.perform(.escape, makeFirstResponder: false, scrollSelectionIntoView: false)
        }

        // When: 호스트가 소비한다고 답한다.
        controller.onUnhandledAction = { _ in true }
        let handled = controller.handleNativeCommand(AppKitCommandSelectors.cancelOperation)

        // 호스트가 기본 처리로 넘긴다고 답한다.
        controller.onUnhandledAction = { _ in false }
        let notHandled = controller.handleNativeCommand(AppKitCommandSelectors.cancelOperation)

        // Then
        #expect(handled)
        #expect(!notHandled)
    }

    @Test("콜백이 없으면 native escape는 기존대로 소비된 것으로 보고된다")
    func nativeEscapeKeepsItsDefaultWithoutACallback() {
        // Given
        let controller = makeController()
        for _ in 0..<3 {
            controller.perform(.escape, makeFirstResponder: false, scrollSelectionIntoView: false)
        }

        // When
        let handled = controller.handleNativeCommand(AppKitCommandSelectors.cancelOperation)

        // Then: 회귀 방지 — 이 selector는 engine이 거절해도 true를 돌려주고 있었다.
        #expect(handled)
    }
}

// MARK: - Support

@MainActor
private func makeController() -> AppKitEditorViewController {
    let blockID: BlockID = "block"
    return AppKitEditorViewController(
        blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "Escape target"))],
        selection: .caret(blockID: blockID, offset: 2)
    )
}
