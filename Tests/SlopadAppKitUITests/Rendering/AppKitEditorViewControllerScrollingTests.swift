import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit programmatic scroll")
struct AppKitEditorViewControllerScrollingTests {
    @Test("공개 scroll은 canonical document revision을 변경하지 않는다")
    func preservesDocumentSnapshot() {
        // Given
        let blockIDs = (0..<24).map { BlockID("block-\($0)") }
        let controller = AppKitEditorViewController(
            blocks: blockIDs.map { EditorBlockInput(id: $0) }
        )
        let before = controller.documentSnapshot
        var committedRevisions: [EditorDocumentRevision] = []
        controller.onUpdate = { update in
            if let revision = update.committedDocumentRevision {
                committedRevisions.append(revision)
            }
        }

        // When
        controller.scrollDocument(to: 480)

        // Then
        #expect(committedRevisions.isEmpty)
        #expect(controller.documentSnapshot == before)
    }

    @Test("공개 scroll은 반환 전에 viewport와 visible snapshot을 함께 동기화한다")
    func synchronizesVisibleSnapshot() throws {
        // Given
        let blockIDs = (0..<24).map { BlockID("block-\($0)") }
        let controller = AppKitEditorViewController(
            blocks: blockIDs.enumerated().map { index, blockID in
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(
                        text: "Block \(index)\nSecond line keeps the document scrollable."
                    )
                )
            },
            selection: .caret(blockID: blockIDs[0], offset: 0)
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
        let externalResponder = ProgrammaticScrollFocusView(frame: .zero)
        controller.view.addSubview(externalResponder)
        #expect(window.makeFirstResponder(externalResponder))
        _ = try #require(controller.snapshot)
        var deliveredSnapshots: [EditorSessionSnapshot] = []
        controller.onSnapshotChanged = { deliveredSnapshots.append($0) }

        // When
        controller.scrollDocument(to: 480)

        // Then
        let viewport = controller.currentViewport()
        let snapshot = try #require(controller.snapshot)
        let expectedSnapshot = controller.session.render(in: viewport)
        #expect(viewport.scrollY > 0)
        #expect(!expectedSnapshot.visibleBlocks.isEmpty)
        #expect(snapshot.visibleBlocks.map(\.id) == expectedSnapshot.visibleBlocks.map(\.id))
        #expect(snapshot.totalHeight == expectedSnapshot.totalHeight)
        #expect(abs(Double(controller.canvasView.frame.width) - viewport.width) < 0.5)
        #expect(Double(controller.canvasView.frame.height) >= snapshot.totalHeight)
        #expect(
            deliveredSnapshots.last?.visibleBlocks.map(\.id)
                == snapshot.visibleBlocks.map(\.id)
        )
        #expect(window.firstResponder === externalResponder)
    }

    @Test("공개 scroll은 문서 끝으로 clamp한 viewport와 visible snapshot을 동기화한다")
    func clampsToDocumentEnd() throws {
        // Given
        let blockIDs = (0..<24).map { BlockID("block-\($0)") }
        let controller = AppKitEditorViewController(
            blocks: blockIDs.enumerated().map { index, blockID in
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Block \(index) with scrollable content")
                )
            },
            selection: .caret(blockID: blockIDs[0], offset: 0)
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

        // When
        controller.scrollDocument(to: 100_000)

        // Then
        let viewport = controller.currentViewport()
        let snapshot = try #require(controller.snapshot)
        let maximumY = max(
            0,
            controller.canvasView.frame.height - CGFloat(viewport.height)
        )
        let expectedVisibleBlockIDs = controller.session.render(in: viewport).visibleBlocks.map(\.id)
        #expect(abs(viewport.scrollY - Double(maximumY)) < 0.5)
        #expect(!expectedVisibleBlockIDs.isEmpty)
        #expect(snapshot.visibleBlocks.map(\.id) == expectedVisibleBlockIDs)
        #expect(snapshot.visibleBlocks.contains { $0.id == blockIDs.last })
    }

    @Test("첫 render 전 공개 scroll도 최종 document extent를 기준으로 clamp한다")
    func synchronizesBeforeInitialRender() throws {
        // Given
        let blockIDs = (0..<100).map { BlockID("block-\($0)") }
        let controller = AppKitEditorViewController(
            blocks: blockIDs.enumerated().map { index, blockID in
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Block \(index) with scrollable content")
                )
            },
            selection: .caret(blockID: blockIDs[0], offset: 0)
        )
        #expect(controller.snapshot == nil)

        // When
        controller.scrollDocument(to: 100_000)

        // Then
        let viewport = controller.currentViewport()
        let snapshot = try #require(controller.snapshot)
        let maximumY = max(
            0,
            controller.canvasView.frame.height - CGFloat(viewport.height)
        )
        let expectedVisibleBlockIDs = controller.session.render(in: viewport).visibleBlocks.map(\.id)
        #expect(abs(viewport.scrollY - Double(maximumY)) < 0.5)
        #expect(snapshot.visibleBlocks.map(\.id) == expectedVisibleBlockIDs)
        #expect(snapshot.visibleBlocks.contains { $0.id == blockIDs.last })
    }

    @Test("첫 render 전 공개 scroll은 보이는 active native surface도 초기화한다")
    func initializesNativeSurfaceBeforeInitialRender() throws {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Visible native input")
                )
            ],
            selection: .caret(blockID: blockID, offset: 4)
        )
        #expect(controller.snapshot == nil)

        // When
        controller.scrollDocument(to: 0)

        // Then
        let snapshot = try #require(controller.snapshot)
        #expect(snapshot.activeTextInput?.renderDescriptor.measureRequest.blockID == blockID)
        #expect(controller.activeNativeText == "Visible native input")
        #expect(controller.activeNativeSelectedRange == NSRange(location: 4, length: 0))
    }

    @Test("공개 scroll은 live marked text와 native selection을 보존한다")
    func preservesMarkedText() {
        // Given
        let blockIDs = (0..<16).map { BlockID("block-\($0)") }
        let controller = AppKitEditorViewController(
            blocks: blockIDs.enumerated().map { index, blockID in
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Block \(index) with scrollable content")
                )
            },
            selection: .caret(blockID: blockIDs[0], offset: 2)
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
        #expect(window.makeFirstResponder(controller.canvasView))
        controller.setMarkedTextFromNativeSurface(
            "한글",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let textBeforeScroll = controller.activeNativeText
        let selectionBeforeScroll = controller.activeNativeSelectedRange
        let markedRangeBeforeScroll = controller.activeNativeMarkedRange
        let viewportBeforeScroll = controller.currentViewport()
        #expect(controller.hasActiveNativeMarkedText)

        // When
        controller.scrollDocument(to: 40)

        // Then
        #expect(controller.currentViewport().scrollY > viewportBeforeScroll.scrollY)
        #expect(controller.activeNativeText == textBeforeScroll)
        #expect(controller.activeNativeSelectedRange == selectionBeforeScroll)
        #expect(controller.activeNativeMarkedRange == markedRangeBeforeScroll)
        #expect(controller.hasActiveNativeMarkedText)
        #expect(window.firstResponder === controller.canvasView)
    }

    @Test("실제 scroll bounds 변경도 live marked text와 동기화된 snapshot을 보존한다")
    func preservesMarkedTextDuringBoundsChange() throws {
        // Given
        let blockIDs = (0..<16).map { BlockID("block-\($0)") }
        let controller = AppKitEditorViewController(
            blocks: blockIDs.enumerated().map { index, blockID in
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Block \(index) with scrollable content")
                )
            },
            selection: .caret(blockID: blockIDs[0], offset: 2)
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
        #expect(window.makeFirstResponder(controller.canvasView))
        controller.setMarkedTextFromNativeSurface(
            "한글",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let textBeforeScroll = controller.activeNativeText
        let selectionBeforeScroll = controller.activeNativeSelectedRange
        let markedRangeBeforeScroll = controller.activeNativeMarkedRange
        let viewportBeforeScroll = controller.currentViewport()
        var callbackObservedPreservedNativeState = false
        controller.onSnapshotChanged = { _ in
            callbackObservedPreservedNativeState =
                controller.activeNativeText == textBeforeScroll
                && controller.activeNativeSelectedRange == selectionBeforeScroll
                && controller.activeNativeMarkedRange == markedRangeBeforeScroll
                && controller.hasActiveNativeMarkedText
        }

        // When
        controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 40))
        controller.scrollView.reflectScrolledClipView(controller.scrollView.contentView)

        // Then
        let viewport = controller.currentViewport()
        let snapshot = try #require(controller.snapshot)
        let expectedVisibleBlockIDs = controller.session.render(in: viewport).visibleBlocks.map(\.id)
        #expect(viewport.scrollY > viewportBeforeScroll.scrollY)
        #expect(snapshot.visibleBlocks.map(\.id) == expectedVisibleBlockIDs)
        #expect(callbackObservedPreservedNativeState)
        #expect(controller.activeNativeText == textBeforeScroll)
        #expect(controller.activeNativeSelectedRange == selectionBeforeScroll)
        #expect(controller.activeNativeMarkedRange == markedRangeBeforeScroll)
        #expect(controller.hasActiveNativeMarkedText)
        #expect(window.firstResponder === controller.canvasView)
    }
}

@MainActor
private final class ProgrammaticScrollFocusView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}
