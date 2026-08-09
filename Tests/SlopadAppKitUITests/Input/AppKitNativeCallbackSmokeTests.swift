import AppKit
import SlopadEngine
import Testing

@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit native callback smoke")
struct AppKitNativeCallbackSmokeTests {
    @Test("window mouse event가 canvas callback을 거쳐 focus와 text selection을 동기화한다")
    func mouseEventSelectsTextThroughCanvasCallback() throws {
        // Given
        let blockID: BlockID = "pointer"
        let host = NativeCallbackTestHost(
            blockID: blockID,
            text: "Pointer selection",
            selection: .inactive
        )
        defer { host.close() }
        let renderedBlock = try #require(host.controller.snapshot?.visibleBlocks.first)
        let textFrame = renderedBlock.textRender.frame
        let documentPoint = CGPoint(
            x: textFrame.x + 8,
            y: textFrame.y + (textFrame.height / 2)
        )

        // When
        try host.dispatchMouseClick(at: documentPoint)

        // Then
        #expect(host.window.firstResponder === host.controller.canvasView)
        #expect(host.controller.isFocused)
        guard case .caret(let position) = host.controller.snapshot?.selection else {
            Issue.record("window가 전달한 mouseDown이 caret selection을 만들지 않음")
            return
        }
        #expect(position.blockID == blockID)
        #expect(host.controller.snapshot?.activeTextInput != nil)
        #expect(host.controller.snapshot?.visibleBlocks.first?.id == blockID)
        #expect(host.controller.documentSnapshot.blocks.first?.content.text == "Pointer selection")
    }

    @Test("window key event가 keyDown과 NSTextInputClient insertText를 거쳐 문서를 수정한다")
    func keyEventInsertsTextThroughNativeCallbacks() throws {
        // Given
        let blockID: BlockID = "keyboard"
        let host = NativeCallbackTestHost(
            blockID: blockID,
            text: "A",
            selection: .caret(blockID: blockID, offset: 1)
        )
        defer { host.close() }
        host.controller.setFocused(true)
        var committedRevisions: [EditorDocumentRevision] = []
        host.controller.onUpdate = { update in
            if let revision = update.committedDocumentRevision {
                committedRevisions.append(revision)
            }
        }

        // When
        try host.dispatchKeyDown(characters: "x", keyCode: 7)

        // Then
        #expect(host.window.firstResponder === host.controller.canvasView)
        #expect(host.controller.isFocused)
        #expect(host.controller.documentSnapshot.blocks.first?.content.text == "Ax")
        #expect(committedRevisions.map(\.rawValue) == [1])
        #expect(host.controller.snapshot?.selection == .caret(blockID: blockID, offset: 2))
        #expect(
            host.controller.snapshot?.visibleBlocks.first?.textRender.measureRequest.text == "Ax"
        )
    }

    @Test("NSTextInputClient marked text는 commit 전 canonical 문서를 바꾸지 않고 한 번만 확정한다")
    func markedTextCommitsCanonicalDocumentOnce() throws {
        // Given
        let blockID: BlockID = "composition"
        let host = NativeCallbackTestHost(
            blockID: blockID,
            text: "A",
            selection: .caret(blockID: blockID, offset: 1)
        )
        defer { host.close() }
        host.controller.setFocused(true)
        var committedRevisions: [EditorDocumentRevision] = []
        host.controller.onUpdate = { update in
            if let revision = update.committedDocumentRevision {
                committedRevisions.append(revision)
            }
        }

        // When: 입력기 서버가 호출하는 NSTextInputClient 경계를 직접 구동한다.
        host.controller.canvasView.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        // Then: marked text와 selection/rendering은 adapter에 보이지만 canonical 문서는 그대로다.
        #expect(host.controller.canvasView.hasMarkedText())
        #expect(host.controller.documentSnapshot.revision.rawValue == 0)
        #expect(host.controller.documentSnapshot.blocks.first?.content.text == "A")
        #expect(committedRevisions.isEmpty)
        #expect(host.controller.snapshot?.composition?.text == "한")
        #expect(host.controller.snapshot?.selection == .caret(blockID: blockID, offset: 2))
        #expect(
            host.controller.snapshot?.visibleBlocks.first?.textRender.measureRequest.text == "A한"
        )

        // When: AppKit의 일반적인 IME 확정 callback을 같은 native client에 전달한다.
        host.controller.canvasView.insertText(
            "한",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        // Then
        #expect(!host.controller.canvasView.hasMarkedText())
        #expect(host.controller.snapshot?.composition == nil)
        #expect(host.controller.documentSnapshot.blocks.first?.content.text == "A한")
        #expect(committedRevisions.map(\.rawValue) == [1])
        #expect(host.controller.snapshot?.selection == .caret(blockID: blockID, offset: 2))
        #expect(
            host.controller.snapshot?.visibleBlocks.first?.textRender.measureRequest.text == "A한"
        )
    }
}

// MARK: - Native AppKit Host

/// Mounts the production controller in an `NSWindow` and enters through AppKit's event or
/// `NSTextInputClient` boundary. It deliberately exposes no Session/semantic input helper.
@MainActor
private final class NativeCallbackTestHost {
    let controller: AppKitEditorViewController
    let window: NSWindow

    init(blockID: BlockID, text: String, selection: EditorSelection) {
        _ = NSApplication.shared
        controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: text))],
            selection: selection,
            focusOnAppear: false
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 240)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
    }

    func dispatchMouseClick(at documentPoint: CGPoint) throws {
        let windowPoint = controller.canvasView.convert(documentPoint, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type,
                    location: windowPoint,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: type == .leftMouseDown ? 1 : 0
                )
            )
            window.sendEvent(event)
        }
    }

    func dispatchKeyDown(characters: String, keyCode: UInt16) throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            )
        )
        window.sendEvent(event)
    }

    func close() {
        controller.setFocused(false)
        window.orderOut(nil)
        window.contentViewController = nil
        window.close()
    }
}
