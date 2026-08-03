import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit active input 조합 전달")
struct AppKitActiveInputControllerCompositionTests {
    @Test("marked 선택은 최초 begin과 후속 update 뒤 유효 grapheme 범위로 전달된다")
    func forwardsMarkedSelectionInEffectiveText() throws {
        // Given
        let blockID: BlockID = "block"
        let owner = CompositionRecordingOwner(
            blockID: blockID,
            text: "A🙂B",
            selection: .caret(blockID: blockID, offset: 1)
        )
        let inputController = try owner.makeInputController()

        // When
        inputController.setMarkedText(
            "x🙂y",
            selectedRange: NSRange(location: 1, length: 2),
            replacementRange: NSRange(location: 1, length: 2)
        )
        inputController.setMarkedText(
            "pq",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        // Then
        #expect(
            owner.receivedEvents
                == [
                    .beginComposition(
                        blockID: blockID,
                        replacementRange: TextRange(1, 2),
                        text: "x🙂y"
                    ),
                    .activeTextSelectionChanged(
                        blockID: blockID,
                        selectedRange: TextRange(2, 3)
                    ),
                    .updateComposition(
                        blockID: blockID,
                        replacementRange: TextRange(1, 2),
                        text: "pq"
                    ),
                    .activeTextSelectionChanged(
                        blockID: blockID,
                        selectedRange: TextRange.point(2)
                    ),
                ]
        )
        #expect(inputController.activeText == "ApqB")
        #expect(inputController.activeSelectedRange == NSRange(location: 2, length: 0))
    }

    @Test("unmark는 조합을 취소하지 않고 native 선택과 함께 문서에 확정한다")
    func commitsMarkedTextOnUnmark() throws {
        // Given
        let blockID: BlockID = "block"
        let owner = CompositionRecordingOwner(
            blockID: blockID,
            text: "AB",
            selection: .caret(blockID: blockID, offset: 1)
        )
        let inputController = try owner.makeInputController()
        inputController.setMarkedText(
            "한글",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        // When
        inputController.unmarkText()
        owner.controller.renderAndSyncSurface(makeFirstResponder: false)
        let snapshot = try #require(owner.controller.snapshot)

        // Then
        #expect(
            owner.receivedEvents
                == [
                    .beginComposition(
                        blockID: blockID,
                        replacementRange: TextRange.point(1),
                        text: "한글"
                    ),
                    .activeTextSelectionChanged(
                        blockID: blockID,
                        selectedRange: TextRange.point(2)
                    ),
                    .commitComposition,
                    .activeTextSelectionChanged(
                        blockID: blockID,
                        selectedRange: TextRange.point(2)
                    ),
                ]
        )
        #expect(snapshot.composition == nil)
        #expect(snapshot.selection == .caret(blockID: blockID, offset: 2))
        #expect(snapshot.visibleBlocks.first?.textRender.measureRequest.text == "A한글B")
        #expect(!inputController.hasMarkedText)
    }

    @Test("조합 확정 insert는 effective text 길이와 무관하게 최초 canonical 대체 범위를 사용한다")
    func insertsUsingCanonicalMarkedReplacementRange() throws {
        // Given
        let blockID: BlockID = "block"
        let owner = CompositionRecordingOwner(
            blockID: blockID,
            text: "A🙂B",
            selection: .caret(blockID: blockID, offset: 1)
        )
        let inputController = try owner.makeInputController()
        inputController.setMarkedText(
            "한국어",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: 1, length: 2)
        )

        // When
        inputController.insertText(
            "X",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        owner.controller.renderAndSyncSurface(makeFirstResponder: false)
        let snapshot = try #require(owner.controller.snapshot)

        // Then
        #expect(
            owner.receivedEvents.suffix(2)
                == [
                    .cancelComposition,
                    .command(
                        .replaceText(
                            blockID: blockID,
                            range: TextRange(1, 2),
                            text: "X"
                        )
                    ),
                ]
        )
        #expect(snapshot.composition == nil)
        #expect(snapshot.visibleBlocks.first?.textRender.measureRequest.text == "AXB")
    }
}

@MainActor
private final class CompositionRecordingOwner: AppKitActiveInputOwner {
    let controller: AppKitEditorViewController
    private let blockID: BlockID
    private(set) var receivedEvents: [EditorInputEvent] = []

    init(blockID: BlockID, text: String, selection: EditorSelection) {
        self.blockID = blockID
        self.controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: text)
                )
            ],
            selection: selection
        )
    }

    func makeInputController() throws -> AppKitActiveInputController {
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let activeTextInput = try #require(controller.snapshot?.activeTextInput)
        let inputController = AppKitActiveInputController(owner: self)
        inputController.sync(activeTextInput: activeTextInput)
        return inputController
    }

    func documentTextForNativeInput(blockID: BlockID) -> String? {
        guard
            blockID == self.blockID,
            let activeTextInput = controller.snapshot?.activeTextInput,
            activeTextInput.renderDescriptor.measureRequest.blockID == blockID
        else { return nil }
        return activeTextInput.renderDescriptor.measureRequest.text
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
        EditorViewport(width: 320, scrollY: 0, height: 240)
    }
}
