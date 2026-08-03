import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit 런타임 에디터 스타일")
struct AppKitEditorViewControllerStyleTests {
    @Test("스타일 변경은 layout과 chrome을 같은 파이프라인으로 갱신하고 snapshot을 한 번 발행한다")
    func synchronizesTextPipeline() throws {
        // Given
        let blockID: BlockID = "block"
        let initialStyle = AppKitEditorStyle(
            fontSize: 12,
            lineHeightMultiple: 1.1,
            gutterWidth: 30,
            contentHorizontalPadding: 8
        )
        let replacementStyle = AppKitEditorStyle(
            fontSize: 28,
            lineHeightMultiple: 1.4,
            gutterWidth: 72,
            contentHorizontalPadding: 24
        )
        let chromeRenderer = StyleRecordingChromeRenderer()
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(
                        text: "Runtime style replacement must remeasure wrapped text coherently."
                    )
                )
            ],
            selection: .caret(blockID: blockID, offset: 0),
            style: initialStyle,
            blockChromeRenderer: chromeRenderer
        )
        let window = makeWindow(controller: controller)
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let originalSnapshot = try #require(controller.snapshot)
        let originalBlock = try #require(originalSnapshot.visibleBlocks.first)
        controller.canvasView.needsDisplay = false
        var deliveredSnapshots: [EditorSessionSnapshot] = []
        var callbackObservedStyle = false
        var callbackObservedCanvasSize = false
        var callbackObservedDisplayInvalidation = false
        controller.onSnapshotChanged = { snapshot in
            deliveredSnapshots.append(snapshot)
            callbackObservedStyle = controller.editorStyle == replacementStyle
            callbackObservedCanvasSize =
                controller.canvasView.frame.height >= CGFloat(snapshot.totalHeight)
            callbackObservedDisplayInvalidation = controller.canvasView.needsDisplay
        }

        // When
        controller.updateEditorStyle(replacementStyle)
        _ = try drawOnce(controller)

        // Then
        let replacementSnapshot = try #require(controller.snapshot)
        let replacementBlock = try #require(replacementSnapshot.visibleBlocks.first)
        #expect(controller.editorStyle == replacementStyle)
        #expect(replacementSnapshot.revision != originalSnapshot.revision)
        #expect(replacementBlock.frame.height > originalBlock.frame.height)
        #expect(replacementBlock.textRender.frame.x > originalBlock.textRender.frame.x)
        #expect(replacementBlock.textRender.frame.width < originalBlock.textRender.frame.width)
        #expect(deliveredSnapshots.count == 1)
        #expect(deliveredSnapshots.first?.revision == replacementSnapshot.revision)
        #expect(callbackObservedStyle)
        #expect(callbackObservedCanvasSize)
        #expect(callbackObservedDisplayInvalidation)
        #expect(chromeRenderer.styles == [replacementStyle])
        #expect(window.contentViewController === controller)
    }

    @Test("스타일 변경은 marked text와 native selection, viewport, editor focus를 보존한다")
    func preservesMarkedTextAndEditorFocus() throws {
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
        let window = makeWindow(controller: controller)
        controller.renderAndSyncSurface(makeFirstResponder: false)
        #expect(window.makeFirstResponder(controller.canvasView))
        _ = controller.perform(
            .insertText("X"),
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )
        controller.setMarkedTextFromNativeSurface(
            "한글",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let originalSnapshot = try #require(controller.snapshot)
        #expect(originalSnapshot.history.canUndo)
        let nativeText = controller.activeNativeText
        let nativeSelection = controller.activeNativeSelectedRange
        let nativeMarkedRange = controller.activeNativeMarkedRange
        let viewport = controller.currentViewport()
        var deliveredSnapshots: [EditorSessionSnapshot] = []
        controller.onSnapshotChanged = { deliveredSnapshots.append($0) }
        let replacementStyle = AppKitEditorStyle(
            fontSize: 18,
            lineHeightMultiple: 1.3,
            gutterWidth: 52
        )

        // When
        controller.updateEditorStyle(replacementStyle)

        // Then
        let replacementSnapshot = try #require(controller.snapshot)
        #expect(replacementSnapshot.revision != originalSnapshot.revision)
        #expect(replacementSnapshot.selection == originalSnapshot.selection)
        #expect(replacementSnapshot.composition == originalSnapshot.composition)
        #expect(replacementSnapshot.history.canUndo == originalSnapshot.history.canUndo)
        #expect(replacementSnapshot.history.canRedo == originalSnapshot.history.canRedo)
        #expect(controller.activeNativeText == nativeText)
        #expect(controller.activeNativeSelectedRange == nativeSelection)
        #expect(controller.activeNativeMarkedRange == nativeMarkedRange)
        #expect(controller.hasActiveNativeMarkedText)
        #expect(controller.currentViewport() == viewport)
        #expect(window.firstResponder === controller.canvasView)
        #expect(deliveredSnapshots.count == 1)
    }

    @Test("스타일 변경은 외부 responder를 빼앗지 않는다")
    func preservesExternalResponder() {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "Text"))],
            selection: .caret(blockID: blockID, offset: 0)
        )
        let window = makeWindow(controller: controller)
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let externalResponder = StyleFocusView(frame: .zero)
        controller.view.addSubview(externalResponder)
        #expect(window.makeFirstResponder(externalResponder))

        // When
        controller.updateEditorStyle(AppKitEditorStyle(fontSize: 20))

        // Then
        #expect(window.firstResponder === externalResponder)
    }

    @Test("동일 스타일 변경 요청은 surface를 다시 발행하지 않는다")
    func ignoresIdenticalStyle() throws {
        // Given
        let style = AppKitEditorStyle(fontSize: 17)
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: "block", content: BlockContent(text: "Text"))],
            style: style
        )
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let originalSnapshot = try #require(controller.snapshot)
        var callbackCount = 0
        controller.onSnapshotChanged = { _ in callbackCount += 1 }

        // When
        controller.updateEditorStyle(style)

        // Then
        #expect(controller.snapshot?.revision == originalSnapshot.revision)
        #expect(callbackCount == 0)
    }
}

@MainActor
private final class StyleRecordingChromeRenderer: AppKitBlockChromeRenderer {
    private(set) var styles: [AppKitEditorStyle] = []

    func drawChrome(_ context: AppKitBlockChromeRenderContext) {
        styles.append(context.style)
    }
}

@MainActor
private final class StyleFocusView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

@MainActor
private func makeWindow(controller: AppKitEditorViewController) -> NSWindow {
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

@MainActor
private func drawOnce(_ controller: AppKitEditorViewController) throws -> NSBitmapImageRep {
    let bounds = controller.canvasView.bounds
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(bounds.width.rounded(.up))),
            pixelsHigh: max(1, Int(bounds.height.rounded(.up))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    )
    let graphicsContext = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }
    controller.drawCanvas(bounds)
    graphicsContext.flushGraphics()
    return bitmap
}
