import AppKit
import SlopadEngine
import Testing

@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit active input command 전달", .serialized)
struct AppKitActiveInputControllerCommandTests {
    @Test("단어·선택 확장·단어 삭제 selector는 현재 viewport를 입력 이벤트에 포함한다")
    func forwardsViewport() {
        // Given
        let viewport = EditorViewport(width: 412, scrollY: 37, height: 268)
        let cases: [(selector: Selector, expectedEvent: EditorInputEvent)] = [
            (
                #selector(NSResponder.moveWordLeft(_:)),
                .command(.navigate(.moveWordLeft(viewport: viewport)))
            ),
            (
                #selector(NSResponder.moveWordRight(_:)),
                .command(.navigate(.moveWordRight(viewport: viewport)))
            ),
            (
                #selector(NSResponder.moveLeftAndModifySelection(_:)),
                .command(.navigate(.extendCharacterLeft(viewport: viewport)))
            ),
            (
                #selector(NSResponder.moveRightAndModifySelection(_:)),
                .command(.navigate(.extendCharacterRight(viewport: viewport)))
            ),
            (
                #selector(NSResponder.moveWordLeftAndModifySelection(_:)),
                .command(.navigate(.extendWordLeft(viewport: viewport)))
            ),
            (
                #selector(NSResponder.moveWordRightAndModifySelection(_:)),
                .command(.navigate(.extendWordRight(viewport: viewport)))
            ),
            (
                #selector(NSResponder.deleteWordBackward(_:)),
                .command(.navigate(.deleteWordBackward(viewport: viewport)))
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

    @Test("copy selector는 Slopad typed payload와 plain text를 함께 쓴다")
    func writesStructuredAndPlainClipboardRepresentations() throws {
        // Given
        let payload = EditorClipboardPayload(
            content: .textSlice(
                EditorClipboardTextSlice(blocks: [
                    EditorBlockInput(id: "source", content: BlockContent(text: "copy"))
                ])
            )
        )
        let owner = CommandRecordingOwner(
            viewport: EditorViewport(width: 320, scrollY: 0, height: 200),
            clipboardPlan: EditorClipboardWritePlan(payload: payload, plainText: "copy")
        )
        let inputController = AppKitActiveInputController(owner: owner)
        NSPasteboard.general.clearContents()
        defer { NSPasteboard.general.clearContents() }

        // When
        let handled = inputController.handleCommand(AppKitCommandSelectors.copy)

        // Then
        #expect(handled)
        let data = try #require(
            NSPasteboard.general.data(forType: AppKitClipboardContract.structuredType)
        )
        #expect(try JSONDecoder().decode(EditorClipboardPayload.self, from: data) == payload)
        #expect(NSPasteboard.general.string(forType: .string) == "copy")
    }

    @Test("paste selector는 지원되는 typed payload를 plain text보다 우선한다")
    func prefersSupportedStructuredPaste() throws {
        // Given
        let payload = EditorClipboardPayload(
            content: .textSlice(
                EditorClipboardTextSlice(blocks: [
                    EditorBlockInput(id: "source", content: BlockContent(text: "typed"))
                ])
            )
        )
        let owner = CommandRecordingOwner(
            viewport: EditorViewport(width: 320, scrollY: 0, height: 200)
        )
        let inputController = AppKitActiveInputController(owner: owner)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        pasteboard.setData(
            try JSONEncoder().encode(payload),
            forType: AppKitClipboardContract.structuredType
        )
        pasteboard.setString("fallback", forType: .string)

        // When
        let handled = inputController.handleCommand(AppKitCommandSelectors.paste)

        // Then
        #expect(handled)
        #expect(owner.receivedEvents == [.command(.pasteStructured(payload))])
    }

    @Test("paste selector는 신버전 typed payload를 무시하고 plain text로 fallback한다")
    func fallsBackFromUnsupportedStructuredPaste() throws {
        // Given
        let payload = EditorClipboardPayload(
            version: EditorClipboardPayload.currentVersion + 1,
            content: .textSlice(
                EditorClipboardTextSlice(blocks: [
                    EditorBlockInput(id: "source", content: BlockContent(text: "newer"))
                ])
            )
        )
        let owner = CommandRecordingOwner(
            viewport: EditorViewport(width: 320, scrollY: 0, height: 200)
        )
        let inputController = AppKitActiveInputController(owner: owner)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        pasteboard.setData(
            try JSONEncoder().encode(payload),
            forType: AppKitClipboardContract.structuredType
        )
        pasteboard.setString("fallback", forType: .string)

        // When
        let handled = inputController.handleCommand(AppKitCommandSelectors.paste)

        // Then
        #expect(handled)
        #expect(owner.receivedEvents == [.command(.pasteText("fallback"))])
    }

    @Test("paste selector는 손상되거나 크기 제한을 넘은 typed data를 plain text로 fallback한다")
    func fallsBackFromMalformedAndOversizedStructuredPaste() {
        let invalidRepresentations = [
            Data("not-json".utf8),
            Data(count: AppKitClipboardContract.maximumStructuredBytes + 1),
        ]

        for data in invalidRepresentations {
            // Given
            let owner = CommandRecordingOwner(
                viewport: EditorViewport(width: 320, scrollY: 0, height: 200)
            )
            let pasteboard = RecordingPasteboard()
            pasteboard.dataByType[AppKitClipboardContract.structuredType] = data
            pasteboard.stringByType[.string] = "fallback"
            let inputController = AppKitActiveInputController(
                owner: owner,
                pasteboard: pasteboard
            )

            // When
            let handled = inputController.handleCommand(AppKitCommandSelectors.paste)

            // Then
            #expect(handled)
            #expect(owner.receivedEvents == [.command(.pasteText("fallback"))])
        }
    }

    @Test("필수 clipboard representation 쓰기가 실패하면 cut은 문서를 변경하지 않는다")
    func failedClipboardWritePreventsCut() {
        // Given
        let payload = EditorClipboardPayload(
            content: .textSlice(
                EditorClipboardTextSlice(blocks: [
                    EditorBlockInput(id: "source", content: BlockContent(text: "copy"))
                ])
            )
        )
        let owner = CommandRecordingOwner(
            viewport: EditorViewport(width: 320, scrollY: 0, height: 200),
            clipboardPlan: EditorClipboardWritePlan(payload: payload, plainText: "copy")
        )
        let pasteboard = RecordingPasteboard()
        pasteboard.failingWriteTypes = [.string]
        let inputController = AppKitActiveInputController(owner: owner, pasteboard: pasteboard)

        // When
        let handled = inputController.handleCommand(AppKitCommandSelectors.cut)

        // Then
        #expect(!handled)
        #expect(owner.receivedEvents.isEmpty)
    }
}

@MainActor
private final class RecordingPasteboard: AppKitPasteboardAccess {
    var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
    var stringByType: [NSPasteboard.PasteboardType: String] = [:]
    var failingWriteTypes: Set<NSPasteboard.PasteboardType> = []

    func clearContents() -> Int {
        dataByType.removeAll()
        stringByType.removeAll()
        return 0
    }

    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        guard !failingWriteTypes.contains(dataType), let data else { return false }
        dataByType[dataType] = data
        return true
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        guard !failingWriteTypes.contains(dataType) else { return false }
        stringByType[dataType] = string
        return true
    }

    func data(forType dataType: NSPasteboard.PasteboardType) -> Data? {
        dataByType[dataType]
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        stringByType[dataType]
    }
}

@MainActor
private final class CommandRecordingOwner: AppKitActiveInputOwner {
    private let controller: AppKitEditorViewController
    private let viewport: EditorViewport
    private(set) var receivedEvents: [EditorInputEvent] = []
    private(set) var unhandledActions: [AppKitEditorAction] = []
    var unhandledActionResult: Bool?
    private let clipboardPlan: EditorClipboardWritePlan?

    init(viewport: EditorViewport, clipboardPlan: EditorClipboardWritePlan? = nil) {
        self.viewport = viewport
        self.clipboardPlan = clipboardPlan
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

    func clipboardWritePlan() -> EditorClipboardWritePlan? {
        clipboardPlan
    }

    func handleNativeInputEvent(_ inputEvent: EditorInputEvent) -> EditorUpdate? {
        receivedEvents.append(inputEvent)
        return controller.handleInputWithoutRendering(inputEvent)
    }

    func handleActiveInputRenderRequest(_ request: AppKitActiveInputRenderRequest) {}

    func currentViewport() -> EditorViewport {
        viewport
    }

    func reportUnhandledAction(_ action: AppKitEditorAction, defaultHandled: Bool) -> Bool {
        unhandledActions.append(action)
        return unhandledActionResult ?? defaultHandled
    }
}
