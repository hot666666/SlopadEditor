import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit surface sync 재진입")
struct AppKitEditorViewControllerSurfaceSyncTests {
    @Test("snapshot callback의 동일 render 요청은 재귀 발행하지 않는다")
    func suppressesRecursivePublication() {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Stable snapshot")
                )
            ],
            selection: .caret(blockID: blockID, offset: 0)
        )
        controller.renderAndSyncSurface(makeFirstResponder: false)
        var callbackCount = 0
        controller.onSnapshotChanged = { _ in
            callbackCount += 1
            if callbackCount < 3 {
                controller.renderAndSyncSurface(makeFirstResponder: false)
            }
        }

        // When
        controller.renderAndSyncSurface(makeFirstResponder: false)

        // Then
        #expect(callbackCount == 1)
    }

    @Test("marked text snapshot callback의 동일 full render 요청은 native composition을 덮지 않는다")
    func preservesMarkedTextDuringRecursivePublication() {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Composition target")
                )
            ],
            selection: .caret(blockID: blockID, offset: 2)
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
        #expect(window.makeFirstResponder(controller.canvasView))
        controller.setMarkedTextFromNativeSurface(
            "한글",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let textBeforeCallback = controller.activeNativeText
        let selectionBeforeCallback = controller.activeNativeSelectedRange
        let markedRangeBeforeCallback = controller.activeNativeMarkedRange
        var callbackCount = 0
        controller.onSnapshotChanged = { _ in
            callbackCount += 1
            if callbackCount < 3 {
                controller.renderAndSyncSurface(makeFirstResponder: false)
            }
        }

        // When
        controller.scrollDocument(to: 0)

        // Then
        #expect(callbackCount == 1)
        #expect(controller.activeNativeText == textBeforeCallback)
        #expect(controller.activeNativeSelectedRange == selectionBeforeCallback)
        #expect(controller.activeNativeMarkedRange == markedRangeBeforeCallback)
        #expect(controller.hasActiveNativeMarkedText)
        #expect(window.firstResponder === controller.canvasView)
    }

    @Test("pending full sync 뒤의 preserve 요청은 최신 marked text native state를 유지한다")
    func preservesLatestNativePolicy() throws {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Composition target")
                )
            ],
            selection: .caret(blockID: blockID, offset: 2)
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
        let responder = SurfaceSyncActionOnResignView(frame: .zero)
        controller.view.addSubview(responder)
        var didQueueRequests = false
        responder.onResign = {
            guard !didQueueRequests else { return }
            didQueueRequests = true
            controller.focus(blockID: blockID, offset: 2)
            controller.setMarkedTextFromNativeSurface(
                "한글",
                selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }
        #expect(window.makeFirstResponder(responder))

        // When
        controller.renderAndSyncSurface(makeFirstResponder: true)

        // Then
        let snapshot = try #require(controller.snapshot)
        #expect(didQueueRequests)
        #expect(snapshot.composition?.text == "한글")
        #expect(controller.activeNativeText.contains("한글"))
        #expect(controller.activeNativeMarkedRange.length == "한글".utf16.count)
        #expect(controller.hasActiveNativeMarkedText)
        #expect(window.firstResponder === controller.canvasView)
    }

    @Test("pending full sync들의 focus와 selection reveal 요구는 함께 누적한다")
    func mergesPositiveFullSyncRequirements() throws {
        // Given
        let blockIDs = (0..<30).map { BlockID("block-\($0)") }
        let controller = AppKitEditorViewController(
            blocks: blockIDs.enumerated().map { index, blockID in
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Block \(index) keeps scrolling")
                )
            },
            selection: .caret(blockID: blockIDs[29], offset: 0)
        )
        let window = SurfaceSyncFocusTrackingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        window.trackedResponder = controller.canvasView
        controller.scrollDocument(to: 100_000)
        #expect(controller.snapshot?.activeTextInput != nil)
        let responder = SurfaceSyncActionOnResignView(frame: .zero)
        controller.view.addSubview(responder)
        var didQueueRequests = false
        responder.onResign = {
            guard !didQueueRequests else { return }
            didQueueRequests = true
            controller.focus(blockID: blockIDs[0], offset: 0)
            controller.renderAndSyncSurface(
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        }
        #expect(window.makeFirstResponder(responder))

        // When
        controller.renderAndSyncSurface(makeFirstResponder: true)

        // Then
        let snapshot = try #require(controller.snapshot)
        #expect(didQueueRequests)
        #expect(controller.currentViewport().scrollY == 0)
        #expect(snapshot.selection == .caret(blockID: blockIDs[0], offset: 0))
        #expect(snapshot.activeTextInput?.renderDescriptor.measureRequest.blockID == blockIDs[0])
        #expect(window.firstResponder === controller.canvasView)
        #expect(window.trackedFocusRequestCount == 2)
    }

    @Test("첫 preserve render callback의 full sync는 동일 snapshot의 native surface를 연결한다")
    func synchronizesNativeSurfaceAfterInitialPreserveRender() {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Initial native surface")
                )
            ],
            selection: .caret(blockID: blockID, offset: 4)
        )
        #expect(controller.snapshot == nil)
        #expect(controller.activeNativeText.isEmpty)
        var callbackCount = 0
        controller.onSnapshotChanged = { _ in
            callbackCount += 1
            controller.renderAndSyncSurface(makeFirstResponder: false)
        }

        // When
        controller.renderPreservingNativeSurface()

        // Then
        #expect(callbackCount == 1)
        #expect(controller.activeNativeText == "Initial native surface")
        #expect(controller.activeNativeSelectedRange == NSRange(location: 4, length: 0))
    }

    @Test("동일 snapshot으로 reset한 callback도 숨겨진 native surface를 다시 동기화한다")
    func synchronizesNativeSurfaceAfterSameSnapshotReset() {
        // Given
        let blockID: BlockID = "block"
        let blocks = [
            EditorBlockInput(
                id: blockID,
                content: BlockContent(text: "Same snapshot")
            )
        ]
        let selection = EditorSelection.caret(blockID: blockID, offset: 4)
        let controller = AppKitEditorViewController(blocks: blocks, selection: selection)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: true)
        var callbackCount = 0
        controller.onSnapshotChanged = { _ in
            callbackCount += 1
            controller.resetDocument(blocks: blocks, selection: selection)
        }

        // When
        controller.renderAndSyncSurface(makeFirstResponder: true)

        // Then
        #expect(callbackCount == 1)
        #expect(controller.activeNativeText == "Same snapshot")
        #expect(controller.activeNativeSelectedRange == NSRange(location: 4, length: 0))
        #expect(window.firstResponder === controller.canvasView)
    }

    @Test("pending reset 뒤의 명시적 scroll은 이전 selection reveal보다 최신 동작으로 적용한다")
    func appliesLatestExplicitScrollAfterReset() throws {
        // Given
        let oldBlockID: BlockID = "old"
        let newBlockIDs = (0..<100).map { BlockID("new-\($0)") }
        let replacementBlocks = newBlockIDs.enumerated().map { index, blockID in
            EditorBlockInput(
                id: blockID,
                content: BlockContent(text: "Replacement block \(index)")
            )
        }
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
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let responder = SurfaceSyncActionOnResignView(frame: .zero)
        controller.view.addSubview(responder)
        var didQueueRequests = false
        responder.onResign = {
            guard !didQueueRequests else { return }
            didQueueRequests = true
            controller.resetDocument(
                blocks: replacementBlocks,
                selection: .caret(blockID: newBlockIDs[0], offset: 4)
            )
            controller.scrollDocument(to: 100_000)
        }
        #expect(window.makeFirstResponder(responder))

        // When
        controller.renderAndSyncSurface(makeFirstResponder: true)

        // Then
        let snapshot = try #require(controller.snapshot)
        #expect(didQueueRequests)
        #expect(controller.currentViewport().scrollY > 0)
        #expect(snapshot.visibleBlocks.last?.id == newBlockIDs[99])
        #expect(snapshot.selection == .caret(blockID: newBlockIDs[0], offset: 4))
        #expect(window.firstResponder === controller.canvasView)
    }

    @Test("pending 명시적 scroll 뒤의 selection reveal은 최신 동작으로 적용한다")
    func appliesLatestSelectionRevealAfterExplicitScroll() throws {
        // Given
        let blockIDs = (0..<100).map { BlockID("block-\($0)") }
        let controller = AppKitEditorViewController(
            blocks: blockIDs.enumerated().map { index, blockID in
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Block \(index)")
                )
            },
            selection: .caret(blockID: blockIDs[99], offset: 0)
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
        controller.renderAndSyncSurface(
            makeFirstResponder: false,
            scrollSelectionIntoView: true
        )
        #expect(controller.currentViewport().scrollY > 0)
        #expect(
            controller.snapshot?.activeTextInput?.renderDescriptor.measureRequest.blockID
                == blockIDs[99]
        )
        let responder = SurfaceSyncActionOnResignView(frame: .zero)
        controller.view.addSubview(responder)
        var didQueueRequests = false
        responder.onResign = {
            guard !didQueueRequests else { return }
            didQueueRequests = true
            controller.scrollDocument(to: 100_000)
            controller.focus(blockID: blockIDs[0], offset: 0)
        }
        #expect(window.makeFirstResponder(responder))

        // When
        controller.renderAndSyncSurface(makeFirstResponder: true)

        // Then
        let snapshot = try #require(controller.snapshot)
        #expect(didQueueRequests)
        #expect(controller.currentViewport().scrollY == 0)
        #expect(snapshot.selection == .caret(blockID: blockIDs[0], offset: 0))
        #expect(snapshot.visibleBlocks.first?.id == blockIDs[0])
        #expect(window.firstResponder === controller.canvasView)
    }

    @Test("native focus callback 중 문서 reset도 pending sync로 최종 surface에 반영한다")
    func convergesMutationDuringNativeSync() throws {
        // Given
        let oldBlockID: BlockID = "old"
        let newBlockID: BlockID = "new"
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
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let responder = SurfaceSyncActionOnResignView(frame: .zero)
        controller.view.addSubview(responder)
        var didReset = false
        responder.onResign = {
            guard !didReset else { return }
            didReset = true
            controller.resetDocument(
                blocks: [
                    EditorBlockInput(
                        id: newBlockID,
                        content: BlockContent(text: "Replacement document")
                    )
                ],
                selection: .caret(blockID: newBlockID, offset: 4)
            )
            controller.scrollDocument(to: 0)
        }
        #expect(window.makeFirstResponder(responder))
        var deliveredSnapshots: [EditorSessionSnapshot] = []
        controller.onSnapshotChanged = { deliveredSnapshots.append($0) }

        // When
        controller.renderAndSyncSurface(makeFirstResponder: true)

        // Then
        let snapshot = try #require(controller.snapshot)
        #expect(didReset)
        #expect(snapshot.selection == .caret(blockID: newBlockID, offset: 4))
        #expect(snapshot.visibleBlocks.map(\.id) == [newBlockID])
        #expect(controller.activeNativeText == "Replacement document")
        #expect(controller.activeNativeSelectedRange == NSRange(location: 4, length: 0))
        #expect(deliveredSnapshots.last?.selection == snapshot.selection)
        #expect(
            deliveredSnapshots.last?.visibleBlocks.map(\.id)
                == snapshot.visibleBlocks.map(\.id)
        )
        #expect(window.firstResponder === controller.canvasView)
    }
}

@MainActor
private final class SurfaceSyncActionOnResignView: NSView {
    var onResign: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func resignFirstResponder() -> Bool {
        onResign?()
        return true
    }
}

@MainActor
private final class SurfaceSyncFocusTrackingWindow: NSWindow {
    weak var trackedResponder: NSResponder?
    private(set) var trackedFocusRequestCount = 0

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if responder === trackedResponder {
            trackedFocusRequestCount += 1
        }
        return super.makeFirstResponder(responder)
    }
}
