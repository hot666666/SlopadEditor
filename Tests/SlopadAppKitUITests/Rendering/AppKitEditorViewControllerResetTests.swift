import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit 문서 reset")
struct AppKitEditorViewControllerResetTests {
    @Test("공개 reset은 새 baseline snapshot을 제공하고 committed update를 발행하지 않는다")
    func replacesDocumentSnapshotBaseline() {
        // Given
        let oldID: BlockID = "old"
        let newID: BlockID = "new"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: oldID, content: BlockContent(text: "Old"))]
        )
        var committedRevisions: [EditorDocumentRevision] = []
        controller.onUpdate = { update in
            if let revision = update.committedDocumentRevision {
                committedRevisions.append(revision)
            }
        }

        // When
        controller.resetDocument(
            blocks: [EditorBlockInput(id: newID, content: BlockContent(text: "New"))]
        )

        // Then
        #expect(committedRevisions.isEmpty)
        #expect(controller.documentSnapshot.revision.rawValue == 0)
        #expect(controller.documentSnapshot.blocks.map(\.id) == [newID])
        #expect(controller.documentSnapshot.blocks.first?.content.text == "New")
    }

    @Test("공개 reset은 반환 전에 새 문서와 native surface를 함께 동기화한다")
    func synchronizesSurface() throws {
        // Given
        let oldBlockID: BlockID = "old"
        let newBlockIDs = (0..<40).map { BlockID("new-\($0)") }
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: oldBlockID,
                    content: BlockContent(text: "Old document")
                )
            ],
            selection: .caret(blockID: oldBlockID, offset: 0)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let oldCanvasHeight = controller.canvasView.frame.height
        #expect(window.makeFirstResponder(controller.canvasView))
        controller.canvasView.needsDisplay = false
        var deliveredSnapshots: [EditorSessionSnapshot] = []
        var callbackObservedSynchronizedSurface = false
        controller.onSnapshotChanged = { snapshot in
            deliveredSnapshots.append(snapshot)
            if snapshot.selection == .caret(blockID: newBlockIDs[0], offset: 3) {
                callbackObservedSynchronizedSurface =
                    controller.canvasView.frame.height > oldCanvasHeight
                    && controller.canvasView.needsDisplay
                    && controller.activeNativeText == "New block 0"
                    && controller.activeNativeSelectedRange
                        == NSRange(location: 3, length: 0)
            }
        }

        // When
        controller.resetDocument(
            blocks: newBlockIDs.enumerated().map { index, blockID in
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "New block \(index)")
                )
            },
            selection: .caret(blockID: newBlockIDs[0], offset: 3)
        )

        // Then
        let snapshot = try #require(controller.snapshot)
        #expect(snapshot.selection == .caret(blockID: newBlockIDs[0], offset: 3))
        #expect(snapshot.visibleBlocks.contains { $0.id == newBlockIDs[0] })
        #expect(snapshot.visibleBlocks.allSatisfy { $0.id != oldBlockID })
        #expect(controller.canvasView.frame.height > oldCanvasHeight)
        #expect(controller.canvasView.needsDisplay)
        #expect(controller.activeNativeText == "New block 0")
        #expect(controller.activeNativeSelectedRange == NSRange(location: 3, length: 0))
        #expect(callbackObservedSynchronizedSurface)
        #expect(deliveredSnapshots.last?.selection == snapshot.selection)
        #expect(
            deliveredSnapshots.last?.visibleBlocks.map(\.id)
                == snapshot.visibleBlocks.map(\.id)
        )
        #expect(window.firstResponder === controller.canvasView)
    }

    @Test("공개 reset은 짧아진 문서의 clamp된 viewport로 다시 동기화한다")
    func synchronizesClampedViewport() throws {
        // Given
        let oldBlockIDs = (0..<40).map { BlockID("old-\($0)") }
        let newBlockID: BlockID = "new"
        let controller = AppKitEditorViewController(
            blocks: oldBlockIDs.enumerated().map { index, blockID in
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Old block \(index) keeps scrolling")
                )
            },
            selection: .caret(blockID: oldBlockIDs[0], offset: 0)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        controller.scrollDocument(to: 480)
        #expect(controller.currentViewport().scrollY > 0)
        var deliveredSnapshots: [EditorSessionSnapshot] = []
        controller.onSnapshotChanged = { deliveredSnapshots.append($0) }

        // When
        controller.resetDocument(
            blocks: [
                EditorBlockInput(
                    id: newBlockID,
                    content: BlockContent(text: "Short replacement")
                )
            ],
            selection: .caret(blockID: newBlockID, offset: 5)
        )

        // Then
        let viewport = controller.currentViewport()
        let snapshot = try #require(controller.snapshot)
        let expectedVisibleBlockIDs = controller.session.render(in: viewport).visibleBlocks.map(\.id)
        #expect(viewport.scrollY == 0)
        #expect(snapshot.visibleBlocks.map(\.id) == expectedVisibleBlockIDs)
        #expect(snapshot.visibleBlocks.map(\.id) == [newBlockID])
        #expect(snapshot.selection == .caret(blockID: newBlockID, offset: 5))
        #expect(controller.activeNativeText == "Short replacement")
        #expect(controller.activeNativeSelectedRange == NSRange(location: 5, length: 0))
        #expect(
            deliveredSnapshots.last?.visibleBlocks.map(\.id)
                == snapshot.visibleBlocks.map(\.id)
        )
    }

    @Test("공개 reset은 긴 교체 문서의 화면 밖 caret을 reveal하고 native surface를 연결한다")
    func revealsOffscreenSelection() throws {
        // Given
        let oldBlockIDs = (0..<40).map { BlockID("old-\($0)") }
        let newBlockIDs = (0..<40).map { BlockID("new-\($0)") }
        let controller = AppKitEditorViewController(
            blocks: oldBlockIDs.enumerated().map { index, blockID in
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Old block \(index) keeps scrolling")
                )
            },
            selection: .caret(blockID: oldBlockIDs[0], offset: 0)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        controller.scrollDocument(to: 480)
        #expect(controller.currentViewport().scrollY > 0)
        #expect(window.makeFirstResponder(controller.canvasView))

        // When
        controller.resetDocument(
            blocks: newBlockIDs.enumerated().map { index, blockID in
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "New block \(index) keeps scrolling")
                )
            },
            selection: .caret(blockID: newBlockIDs[0], offset: 3)
        )

        // Then
        let snapshot = try #require(controller.snapshot)
        #expect(controller.currentViewport().scrollY == 0)
        #expect(snapshot.visibleBlocks.contains { $0.id == newBlockIDs[0] })
        #expect(snapshot.activeTextInput?.renderDescriptor.measureRequest.blockID == newBlockIDs[0])
        #expect(controller.activeNativeText == "New block 0 keeps scrolling")
        #expect(controller.activeNativeSelectedRange == NSRange(location: 3, length: 0))
        #expect(window.firstResponder === controller.canvasView)
    }

    @Test("공개 reset은 외부 responder의 focus를 빼앗지 않는다")
    func preservesExternalResponder() {
        // Given
        let oldBlockID: BlockID = "old"
        let newBlockID: BlockID = "new"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: oldBlockID, content: BlockContent(text: "Old"))],
            selection: .caret(blockID: oldBlockID, offset: 0)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let externalResponder = ResetFocusView(frame: .zero)
        controller.view.addSubview(externalResponder)
        #expect(window.makeFirstResponder(externalResponder))

        // When
        controller.resetDocument(
            blocks: [EditorBlockInput(id: newBlockID, content: BlockContent(text: "New"))],
            selection: .caret(blockID: newBlockID, offset: 0)
        )

        // Then
        #expect(window.firstResponder === externalResponder)
    }
}

@MainActor
private final class ResetFocusView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}
