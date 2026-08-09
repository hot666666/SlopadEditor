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

    @Test("NSTextInputClient marked text는 canonical 문서를 live 갱신하고 revision은 한 번만 확정한다")
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

        // Then: marked text는 actual editing content지만 아직 committed revision은 없다.
        #expect(host.controller.canvasView.hasMarkedText())
        #expect(host.controller.documentSnapshot.revision.rawValue == 0)
        #expect(host.controller.documentSnapshot.blocks.first?.content.text == "A한")
        #expect(committedRevisions.isEmpty)
        #expect(host.controller.snapshot?.composition?.text == "한")
        #expect(host.controller.snapshot?.selection == .caret(blockID: blockID, offset: 2))
        #expect(
            host.controller.snapshot?.visibleBlocks.first?.textRender.measureRequest.text == "A한"
        )

        // When: 같은 native composition session이 marked text를 갱신한다.
        host.controller.canvasView.setMarkedText(
            "한국",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        // Then
        #expect(host.controller.documentSnapshot.revision.rawValue == 0)
        #expect(host.controller.documentSnapshot.blocks.first?.content.text == "A한국")
        #expect(committedRevisions.isEmpty)

        // When: AppKit의 일반적인 IME 확정 callback을 같은 native client에 전달한다.
        host.controller.canvasView.insertText(
            "한국",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        // Then
        #expect(!host.controller.canvasView.hasMarkedText())
        #expect(host.controller.snapshot?.composition == nil)
        #expect(host.controller.documentSnapshot.blocks.first?.content.text == "A한국")
        #expect(committedRevisions.map(\.rawValue) == [1])
        #expect(host.controller.snapshot?.selection == .caret(blockID: blockID, offset: 3))
        #expect(
            host.controller.snapshot?.visibleBlocks.first?.textRender.measureRequest.text == "A한국"
        )
    }

    @Test("TN marked callback begin update commit은 survivor를 live 갱신하고 한 undo로 묶는다")
    func crossBlockMarkedTextUsesLiveCanonicalTransaction() throws {
        // Given
        let a: BlockID = "tn-a"
        let b: BlockID = "tn-b"
        let selection = TextSelection(
            anchor: TextPosition(blockID: b, offset: 3, affinity: .upstream),
            focus: TextPosition(blockID: a, offset: 3, affinity: .downstream)
        )
        let host = NativeCallbackTestHost(
            blocks: [
                EditorBlockInput(id: a, content: BlockContent(text: "abcDEF")),
                EditorBlockInput(id: b, content: BlockContent(text: "GHIjkl")),
            ],
            selection: .text(selection)
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
        host.controller.canvasView.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        // Then
        #expect(host.controller.documentSnapshot.blocks.map(\.content.text) == ["abc한jkl"])
        #expect(host.controller.documentSnapshot.revision.rawValue == 0)
        #expect(committedRevisions.isEmpty)
        #expect(
            host.controller.snapshot?.activeTextInput?.renderDescriptor.measureRequest.blockID
                == a
        )

        // When
        host.controller.canvasView.setMarkedText(
            "한국",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        host.controller.canvasView.insertText(
            "한국",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        // Then
        #expect(host.controller.documentSnapshot.blocks.map(\.content.text) == ["abc한국jkl"])
        #expect(committedRevisions.map(\.rawValue) == [1])
        #expect(host.controller.snapshot?.selection == .caret(blockID: a, offset: 5))

        _ = try #require(controllerUndo(host.controller))
        #expect(host.controller.documentSnapshot.blocks.map(\.content.text) == ["abcDEF", "GHIjkl"])
        #expect(host.controller.snapshot?.selection == .text(selection))
    }
}

// MARK: - Native AppKit Host

/// Mounts the production controller in an `NSWindow` and enters through AppKit's event or
/// `NSTextInputClient` boundary. It deliberately exposes no Session/semantic input helper.
@MainActor
private final class NativeCallbackTestHost {
    let controller: AppKitEditorViewController
    let window: NSWindow

    convenience init(blockID: BlockID, text: String, selection: EditorSelection) {
        self.init(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: text))],
            selection: selection
        )
    }

    init(blocks: [EditorBlockInput], selection: EditorSelection) {
        _ = NSApplication.shared
        controller = AppKitEditorViewController(
            blocks: blocks,
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

@MainActor
private func controllerUndo(_ controller: AppKitEditorViewController) -> EditorUpdate? {
    controller.perform(
        .undo,
        makeFirstResponder: false,
        scrollSelectionIntoView: false
    )
}
