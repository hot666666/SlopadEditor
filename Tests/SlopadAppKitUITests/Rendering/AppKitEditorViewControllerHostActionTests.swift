import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit 공개 host action")
struct AppKitEditorViewControllerHostActionTests {
    @Test("programmatic 이동은 현재 viewport를 adapter 내부에서 주입한다")
    func performsViewportOwnedAction() throws {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "ABC")
                )
            ],
            selection: .caret(blockID: blockID, offset: 2)
        )
        controller.renderAndSyncSurface(makeFirstResponder: false)

        // When
        let update = try #require(
            controller.perform(
                .moveLeft,
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        )

        // Then
        #expect(update.selection == .caret(blockID: blockID, offset: 1))
        #expect(controller.snapshot?.selection == update.selection)
    }

    @Test("programmatic action은 live composition을 먼저 확정하고 native 상태를 동기화한다")
    func commitsCompositionBeforeAction() throws {
        // Given
        let blockID: BlockID = "composition-action"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "AB")
                )
            ],
            selection: .caret(blockID: blockID, offset: 1)
        )
        _ = makeHostActionWindow(controller: controller)
        controller.renderAndSyncSurface(makeFirstResponder: false)
        controller.setMarkedTextFromNativeSurface(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        // When
        let update = try #require(
            controller.perform(
                .insertText("X"),
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        )

        // Then
        #expect(update.committedDocumentRevision?.rawValue == 2)
        #expect(controller.documentSnapshot.blocks.first?.content.text == "A한XB")
        #expect(controller.activeNativeText == "A한XB")
        #expect(controller.snapshot?.composition == nil)
        #expect(!controller.hasActiveNativeMarkedText)
    }

    @Test("lifecycle 조합 확정은 responder와 viewport를 보존하고 full snapshot revision을 발행한다")
    func commitsCompositionPreservingSurface() throws {
        // Given
        let blockID: BlockID = "composition"
        let trailingBlocks = (0..<30).map { index in
            EditorBlockInput(
                id: BlockID("trailing-\(index)"),
                content: BlockContent(text: "Trailing block \(index)")
            )
        }
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "AB")
                )
            ] + trailingBlocks,
            selection: .caret(blockID: blockID, offset: 1)
        )
        let window = makeHostActionWindow(controller: controller)
        controller.renderAndSyncSurface(makeFirstResponder: false)
        #expect(window.makeFirstResponder(controller.canvasView))
        controller.setMarkedTextFromNativeSurface(
            "한글",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        controller.scrollDocument(to: 120)
        let originalViewport = controller.currentViewport()
        let externalResponder = HostActionFocusView(frame: .zero)
        controller.view.addSubview(externalResponder)
        #expect(window.makeFirstResponder(externalResponder))
        var callbackSnapshot: EditorDocumentSnapshot?
        controller.onUpdate = { [weak controller] update in
            guard let revision = update.committedDocumentRevision else { return }
            guard let snapshot = controller?.documentSnapshot else { return }
            #expect(snapshot.revision == revision)
            callbackSnapshot = snapshot
        }

        // When
        let update = try #require(controller.commitActiveComposition())

        // Then
        #expect(update.committedDocumentRevision?.rawValue == 1)
        #expect(controller.snapshot?.composition == nil)
        #expect(!controller.hasActiveNativeMarkedText)
        #expect(controller.currentViewport() == originalViewport)
        #expect(window.firstResponder === externalResponder)
        #expect(callbackSnapshot?.revision == update.committedDocumentRevision)
        #expect(callbackSnapshot?.blocks.first?.content.text == "A한글B")
    }

    @Test("조합 확정의 Markdown shortcut 정규화 결과를 native text와 selection에 반영한다")
    func synchronizesNormalizedCompositionCommit() throws {
        // Given
        let blockID: BlockID = "shortcut-composition"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: blockID)],
            selection: .caret(blockID: blockID, offset: 0)
        )
        _ = makeHostActionWindow(controller: controller)
        controller.renderAndSyncSurface(makeFirstResponder: false)
        controller.setMarkedTextFromNativeSurface(
            "# ",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        // When
        let update = try #require(controller.commitActiveComposition())

        // Then
        let block = try #require(controller.documentSnapshot.blocks.first)
        #expect(update.committedDocumentRevision?.rawValue == 1)
        #expect(block.kind == .heading(level: .h1))
        #expect(block.content.text == "")
        #expect(controller.activeNativeText == "")
        #expect(controller.activeNativeSelectedRange == NSRange(location: 0, length: 0))
        #expect(controller.snapshot?.selection == .caret(blockID: blockID, offset: 0))
        #expect(controller.snapshot?.composition == nil)
        #expect(!controller.hasActiveNativeMarkedText)
    }
}

@MainActor
private final class HostActionFocusView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

@MainActor
private func makeHostActionWindow(controller: AppKitEditorViewController) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentViewController = controller
    controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 140)
    controller.view.layoutSubtreeIfNeeded()
    return window
}
