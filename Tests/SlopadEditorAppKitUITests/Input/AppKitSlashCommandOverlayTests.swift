import AppKit
import Testing

import SlopadEngine
@testable import SlopadEditorAppKitUI

@MainActor
@Suite("AppKit 슬래시 명령 오버레이")
struct AppKitSlashCommandOverlayTests {
    @Test("화살표와 Enter는 canvas first responder를 유지한 채 명령을 적용한다")
    func keyboardSelectionKeepsCanvasFocused() {
        // Given
        let context = SlashContext()
        context.typeSlashQuery("hea")
        #expect(context.controller.isSlashCommandMenuPresented)
        #expect(context.window.firstResponder === context.controller.canvasView)

        // When: filtered heading results start with Heading 1.
        #expect(context.controller.handleNativeCommand(AppKitCommandSelectors.moveDown))
        #expect(context.controller.handleNativeCommand(AppKitCommandSelectors.moveUp))
        #expect(context.controller.handleNativeCommand(AppKitCommandSelectors.insertNewline))

        // Then
        #expect(!context.controller.isSlashCommandMenuPresented)
        #expect(context.window.firstResponder === context.controller.canvasView)
        #expect(context.controller.documentSnapshot.blocks.first?.content.text == "")
        #expect(context.controller.documentSnapshot.blocks.first?.kind == .heading(level: .h1))
    }

    @Test("Escape는 menu만 dismiss하고 canvas focus를 빼앗지 않는다")
    func escapeDismissesWithoutFocusTransfer() {
        // Given
        let context = SlashContext()
        context.typeSlashQuery("")
        #expect(context.controller.isSlashCommandMenuPresented)

        // When
        #expect(context.controller.handleNativeCommand(AppKitCommandSelectors.cancelOperation))
        context.controller.scrollDocument(to: 0)
        context.controller.view.setFrameSize(NSSize(width: 280, height: 180))
        context.controller.view.layoutSubtreeIfNeeded()

        // Then
        #expect(!context.controller.isSlashCommandMenuPresented)
        #expect(context.controller.snapshot?.slashCommand == nil)
        #expect(context.window.firstResponder === context.controller.canvasView)
        #expect(context.controller.documentSnapshot.blocks.first?.content.text == "/")
    }

    @Test("좁고 낮은 host에서도 menu frame은 container 안에 있고 keyboard 선택이 유지된다")
    func narrowHostClampsOverlayAndKeepsKeyboardBehavior() throws {
        // Given
        let context = SlashContext(size: NSSize(width: 120, height: 56))
        context.typeSlashQuery("hea")
        let frame = try #require(context.controller.slashCommandMenuFrame)

        // Then
        #expect(context.controller.view.bounds.contains(frame))

        // When
        #expect(context.controller.handleNativeCommand(AppKitCommandSelectors.insertNewline))

        // Then
        #expect(context.controller.documentSnapshot.blocks.first?.kind == .heading(level: .h1))
        #expect(context.window.firstResponder === context.controller.canvasView)
    }

    @Test("document reset은 이전 slash menu를 닫고 새 Session을 변환하지 않는다")
    func resetDismissesStaleMenu() {
        // Given
        let context = SlashContext()
        context.typeSlashQuery("hea")
        let previousEpoch = context.controller.documentSnapshot.epoch
        #expect(context.controller.isSlashCommandMenuPresented)

        // When
        context.controller.resetDocument(
            blocks: [
                EditorBlockInput(
                    id: context.blockID,
                    content: BlockContent(text: "/hea")
                )
            ],
            selection: .caret(blockID: context.blockID, offset: 4)
        )

        // Then
        #expect(context.controller.documentSnapshot.epoch != previousEpoch)
        #expect(context.controller.documentSnapshot.revision.rawValue == 0)
        #expect(context.controller.documentSnapshot.blocks.first?.content.text == "/hea")
        #expect(context.controller.documentSnapshot.blocks.first?.kind == .paragraph)
        #expect(context.controller.snapshot?.history.canUndo == false)
        #expect(context.controller.snapshot?.slashCommand == nil)
        #expect(!context.controller.isSlashCommandMenuPresented)
    }
}

@MainActor
private final class SlashContext {
    let blockID: BlockID = "slash"
    let controller: AppKitEditorViewController
    let window: NSWindow

    init(size: NSSize = NSSize(width: 420, height: 260)) {
        controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: ""))],
            selection: .caret(blockID: blockID, offset: 0)
        )
        window = AppKitTestWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        controller.setFocused(true)
    }

    func typeSlashQuery(_ query: String) {
        controller.insertTextFromNativeSurface(
            "/",
            replacementRange: controller.activeNativeSelectedRange
        )
        guard !query.isEmpty else { return }
        controller.insertTextFromNativeSurface(
            query,
            replacementRange: controller.activeNativeSelectedRange
        )
    }
}
