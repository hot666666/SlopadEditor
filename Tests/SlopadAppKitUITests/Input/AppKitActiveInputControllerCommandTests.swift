import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit active input command 전달")
struct AppKitActiveInputControllerCommandTests {
    @Test("단어·선택 확장·단어 삭제 selector는 현재 viewport를 입력 이벤트에 포함한다")
    func forwardsViewport() {
        // Given
        let viewport = EditorViewport(width: 412, scrollY: 37, height: 268)
        let cases: [(selector: Selector, expectedEvent: EditorInputEvent)] = [
            (
                #selector(NSResponder.moveWordLeft(_:)),
                .command(.moveWordLeft(viewport: viewport))
            ),
            (
                #selector(NSResponder.moveWordRight(_:)),
                .command(.moveWordRight(viewport: viewport))
            ),
            (
                #selector(NSResponder.moveLeftAndModifySelection(_:)),
                .command(.extendCharacterLeft(viewport: viewport))
            ),
            (
                #selector(NSResponder.moveRightAndModifySelection(_:)),
                .command(.extendCharacterRight(viewport: viewport))
            ),
            (
                #selector(NSResponder.moveWordLeftAndModifySelection(_:)),
                .command(.extendWordLeft(viewport: viewport))
            ),
            (
                #selector(NSResponder.moveWordRightAndModifySelection(_:)),
                .command(.extendWordRight(viewport: viewport))
            ),
            (
                #selector(NSResponder.deleteWordBackward(_:)),
                .command(.deleteWordBackward(viewport: viewport))
            ),
        ]

        for testCase in cases {
            let owner = CommandRecordingOwner(viewport: viewport)
            let inputController = AppKitActiveInputController(owner: owner)

            // When
            let handled = inputController.handleCommand(testCase.selector)

            // Then
            #expect(handled)
            #expect(owner.receivedEvents == [testCase.expectedEvent])
        }
    }
}

@MainActor
private final class CommandRecordingOwner: AppKitActiveInputOwner {
    private let controller: AppKitEditorViewController
    private let viewport: EditorViewport
    private(set) var receivedEvents: [EditorInputEvent] = []

    init(viewport: EditorViewport) {
        self.viewport = viewport
        self.controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: "block",
                    content: BlockContent(text: "alpha beta gamma")
                )
            ],
            selection: .caret(blockID: "block", offset: 8)
        )
    }

    func documentTextForNativeInput(blockID: BlockID) -> String? {
        nil
    }

    func selectedPlainTextForClipboard() -> String? {
        nil
    }

    func handleNativeInputEvent(_ inputEvent: EditorInputEvent) -> EditorUpdate? {
        receivedEvents.append(inputEvent)
        return controller.handleInputWithoutRendering(inputEvent)
    }

    func handleActiveInputRenderRequest(_ request: AppKitActiveInputRenderRequest) {}

    func currentViewport() -> EditorViewport {
        viewport
    }
}
