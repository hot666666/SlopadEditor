#if DEBUG
    import AppKit
    import SlopadEngine
    import Testing

    @testable import SlopadAppKitUI

    @MainActor
    @Suite("AppKit native input trace")
    struct AppKitNativeInputTraceTests {
        @Test("native callback guard 승인과 Session event 결과를 순서대로 기록한다")
        func recordsAcceptedGuardAndEditorEventResult() throws {
            // Given
            let owner = NativeInputTraceRecordingOwner()
            let activeTextInput = try owner.activeTextInput()
            var trace: [AppKitNativeInputTraceEvent] = []
            let inputController = AppKitActiveInputController(
                owner: owner,
                nativeInputTraceHandler: { trace.append($0) }
            )
            inputController.sync(activeTextInput: activeTextInput)
            trace.removeAll()
            owner.receivedEvents.removeAll()

            // When
            inputController.setMarkedText(
                "ㄹ",
                selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )

            // Then
            let guardRecord = try #require(
                trace.first {
                    $0.category == .activeInputGuard && $0.callback == .setMarkedText
                }
            )
            #expect(guardRecord.outcome == .accepted)
            #expect(guardRecord.reason == .forwarded)
            #expect(guardRecord.blockID == owner.blockID.rawValue)
            #expect(guardRecord.syncDepth == 0)

            let beginRecords = trace.filter { $0.editorEvent == .beginComposition }
            #expect(beginRecords.map(\.phase) == [.emitted, .result])
            #expect(beginRecords.last?.outcome == .handled)
            #expect(beginRecords.last?.committedRevision == nil)
            #expect(
                owner.receivedEvents.first
                    == .beginComposition(
                        blockID: owner.blockID,
                        replacementRange: .point(0),
                        text: "ㄹ"
                    )
            )
        }

        @Test("Session surface sync 중 재진입한 native callback은 instance guard 거절로 기록한다")
        func recordsRejectedReentrantCallbackWithoutGlobalState() throws {
            // Given
            let owner = NativeInputTraceRecordingOwner()
            let activeTextInput = try owner.activeTextInput()
            var trace: [AppKitNativeInputTraceEvent] = []
            var reentrantController: AppKitActiveInputController?
            var attemptedReentry = false
            let inputController = AppKitActiveInputController(
                owner: owner,
                nativeInputTraceHandler: { event in
                    trace.append(event)
                    guard
                        !attemptedReentry,
                        event.category == .nativeSurfaceSync,
                        event.phase == .during
                    else { return }
                    attemptedReentry = true
                    reentrantController?.insertText(
                        "x",
                        replacementRange: NSRange(location: NSNotFound, length: 0)
                    )
                }
            )
            reentrantController = inputController

            // When
            inputController.sync(activeTextInput: activeTextInput)

            // Then
            let rejection = try #require(
                trace.first {
                    $0.category == .activeInputGuard
                        && $0.callback == .insertText
                        && $0.outcome == .rejected
                }
            )
            #expect(rejection.reason == .sessionSynchronization)
            #expect(rejection.syncDepth == 1)
            #expect(rejection.blockID == nil)
            #expect(owner.receivedEvents.isEmpty)
            #expect(inputController.activeText == "")
            let completedSync = try #require(
                trace.last {
                    $0.category == .nativeSurfaceSync && $0.phase == .after
                }
            )
            #expect(completedSync.blockID == owner.blockID.rawValue)
            #expect(completedSync.syncDepth == 0)
            #expect(completedSync.characterCoordinatesInvalidated == false)
        }

        @Test("firstRect 요청은 focus block과 geometry 가용 결과를 함께 기록한다")
        func recordsFirstRectRequestAndResult() throws {
            // Given
            let owner = NativeInputTraceRecordingOwner()
            var trace: [AppKitNativeInputTraceEvent] = []
            owner.controller.nativeInputTraceHandler = { trace.append($0) }
            owner.controller.renderAndSyncSurface(makeFirstResponder: false)
            trace.removeAll()

            // When
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let rect = owner.controller.canvasView.firstRect(
                forCharacterRange: NSRange(location: 0, length: 0),
                actualRange: &actualRange
            )

            // Then
            let firstRectRecords = trace.filter { $0.category == .firstRect }
            #expect(firstRectRecords.map(\.phase) == [.before, .after])
            #expect(firstRectRecords.last?.resultAvailable == true)
            #expect(firstRectRecords.last?.blockID == owner.blockID.rawValue)
            #expect(firstRectRecords.last?.resultRect == AppKitNativeInputTraceRect(rect))
            #expect(actualRange == NSRange(location: 0, length: 0))
        }

        @Test("trace text는 전체 길이만 남기고 앞 16자로 제한한다")
        func boundsEventText() {
            // Given
            let source = String(repeating: "한", count: 20)

            // When
            let text = AppKitNativeInputTraceText(source)

            // Then
            #expect(text.value == String(repeating: "한", count: 16))
            #expect(text.utf16Length == 20)
            #expect(text.truncated)
        }
    }

    @MainActor
    private final class NativeInputTraceRecordingOwner: AppKitActiveInputOwner {
        let blockID: BlockID = "trace-block"
        let controller: AppKitEditorViewController
        var receivedEvents: [EditorInputEvent] = []

        init() {
            controller = AppKitEditorViewController(
                blocks: [
                    EditorBlockInput(id: blockID, content: BlockContent(text: ""))
                ],
                selection: .caret(blockID: blockID, offset: 0)
            )
        }

        func activeTextInput() throws -> EditorSessionActiveTextInputDescriptor {
            controller.renderAndSyncSurface(makeFirstResponder: false)
            return try #require(controller.snapshot?.activeTextInput)
        }

        func documentTextForNativeInput(blockID: BlockID) -> String? {
            guard blockID == self.blockID else { return nil }
            return controller.snapshot?.activeTextInput?.renderDescriptor.measureRequest.text
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

        func reportUnhandledAction(_ action: AppKitEditorAction, defaultHandled: Bool) -> Bool {
            controller.reportUnhandledAction(action, defaultHandled: defaultHandled)
        }
    }
#endif
