import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit 블록 렌더링 경계")
struct AppKitBlockRenderingBoundaryTests {
    @Test("visible block의 chrome 문맥을 host overlay보다 먼저 전달한다")
    func forwardsChromeContextAndOrder() throws {
        // Given
        let blockIDs: [BlockID] = ["a", "b"]
        let blocks = blockIDs.enumerated().map { index, blockID in
            EditorBlockInput(
                id: blockID,
                kind: index == 0 ? .paragraph : .todo(isChecked: false),
                content: BlockContent(text: "Block \(index)")
            )
        }
        let activeRenderer = RecordingBlockChromeRenderer()
        let activeController = makeController(
            blocks: blocks,
            selection: .caret(blockID: blockIDs[0], offset: 0),
            chromeRenderer: activeRenderer
        )
        let selectedRenderer = RecordingBlockChromeRenderer()
        let selectedController = makeController(
            blocks: blocks,
            selection: .blocks(BlockSelection(blockIDs: [blockIDs[1]])),
            chromeRenderer: selectedRenderer
        )
        prepare(activeController)
        prepare(selectedController)
        var drawEvents: [String] = []
        activeRenderer.onDrawChrome = { drawEvents.append("chrome:\($0.rawValue)") }
        activeController.onDrawOverlay = { _, _ in drawEvents.append("overlay") }
        activeController.onDrawCompleted = { _, _ in drawEvents.append("completed") }

        // When
        _ = try drawOnce(activeController)
        _ = try drawOnce(selectedController)

        // Then
        #expect(activeRenderer.records.map(\.id) == blockIDs)
        #expect(activeRenderer.records.map(\.kind) == [.paragraph, .todo(isChecked: false)])
        #expect(activeRenderer.records.map(\.markerKind) == [.none, .todo(isChecked: false)])
        #expect(activeRenderer.records.map(\.depth) == [0, 0])
        #expect(
            activeRenderer.records.map(\.frame)
                == activeController.snapshot?.visibleBlocks.map { CGRect(editorRect: $0.frame) }
        )
        #expect(activeRenderer.records.map(\.isActive) == [true, false])
        #expect(activeRenderer.records.map(\.isSelected) == [false, false])
        #expect(selectedRenderer.records.map(\.isActive) == [false, false])
        #expect(selectedRenderer.records.map(\.isSelected) == [false, true])
        #expect(
            activeRenderer.records.map(\.fontSize)
                == [activeController.editorStyle.fontSize, activeController.editorStyle.fontSize]
        )
        #expect(drawEvents == ["chrome:a", "chrome:b", "overlay", "completed"])
    }

    @Test("host chrome hook과 무관하게 adapter-owned TextKit2 text를 그린다")
    func drawsText() throws {
        // Given
        let textController = makeTextController(
            text: "Visible TextKit2 text",
            selection: .inactive,
            chromeRenderer: PoisoningBlockChromeRenderer()
        )
        let emptyController = makeTextController(
            text: "",
            selection: .inactive,
            chromeRenderer: PoisoningBlockChromeRenderer()
        )

        // When
        let textBitmap = try renderBitmap(for: textController)
        let emptyBitmap = try renderBitmap(for: emptyController)
        let textBlock = try #require(textController.snapshot?.visibleBlocks.first)
        let emptyBlock = try #require(emptyController.snapshot?.visibleBlocks.first)
        let differenceCount = try countPixelDifferences(
            textBitmap,
            emptyBitmap,
            in: textBlock.textRender.frame,
            canvasBounds: textController.canvasView.bounds
        )

        // Then
        #expect(textBlock.frame.height == emptyBlock.frame.height)
        #expect(differenceCount > 10)
    }

    @Test("뒤 block chrome가 앞 block의 TextKit2 text drawing을 덮지 않는다")
    func clipsChromeToBlockFrame() throws {
        // Given
        let textController = makeController(
            blocks: [
                EditorBlockInput(id: "a", content: BlockContent(text: "First block text")),
                EditorBlockInput(id: "b", content: BlockContent(text: "Second block")),
            ],
            selection: .inactive,
            chromeRenderer: OverflowingBlockChromeRenderer()
        )
        let emptyController = makeController(
            blocks: [
                EditorBlockInput(id: "a", content: BlockContent(text: "")),
                EditorBlockInput(id: "b", content: BlockContent(text: "Second block")),
            ],
            selection: .inactive,
            chromeRenderer: OverflowingBlockChromeRenderer()
        )

        // When
        let textBitmap = try renderBitmap(for: textController)
        let emptyBitmap = try renderBitmap(for: emptyController)
        let firstTextFrame = try #require(
            textController.snapshot?.visibleBlocks.first?.textRender.frame
        )
        let differenceCount = try countPixelDifferences(
            textBitmap,
            emptyBitmap,
            in: firstTextFrame,
            canvasBounds: textController.canvasView.bounds
        )

        // Then
        #expect(differenceCount > 10)
    }

    @Test("host chrome hook과 무관하게 focus 위치에 caret feedback을 그린다")
    func drawsCaret() throws {
        // Given
        let text = "Caret positions"
        let leadingController = makeTextController(
            text: text,
            selection: .caret(blockID: "text", offset: 0),
            chromeRenderer: PoisoningBlockChromeRenderer()
        )
        let trailingController = makeTextController(
            text: text,
            selection: .caret(blockID: "text", offset: text.count),
            chromeRenderer: PoisoningBlockChromeRenderer()
        )

        // When
        let leadingBitmap = try renderBitmap(for: leadingController)
        let trailingBitmap = try renderBitmap(for: trailingController)
        let textFrame = try #require(
            leadingController.snapshot?.visibleBlocks.first?.textRender.frame
        )
        let differenceCount = try countPixelDifferences(
            leadingBitmap,
            trailingBitmap,
            in: textFrame,
            canvasBounds: leadingController.canvasView.bounds
        )

        // Then
        #expect(differenceCount > 5)
    }

    @Test("host chrome hook과 무관하게 text selection feedback을 그린다")
    func drawsSelection() throws {
        // Given
        let text = "Selection ranges"
        let focusOffset = 12
        let wideController = makeTextController(
            text: text,
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: "text", offset: 0),
                    focus: TextPosition(blockID: "text", offset: focusOffset)
                )
            ),
            chromeRenderer: PoisoningBlockChromeRenderer()
        )
        let narrowController = makeTextController(
            text: text,
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: "text", offset: 6),
                    focus: TextPosition(blockID: "text", offset: focusOffset)
                )
            ),
            chromeRenderer: PoisoningBlockChromeRenderer()
        )

        // When
        let wideBitmap = try renderBitmap(for: wideController)
        let narrowBitmap = try renderBitmap(for: narrowController)
        let textFrame = try #require(
            wideController.snapshot?.visibleBlocks.first?.textRender.frame
        )
        let differenceCount = try countPixelDifferences(
            wideBitmap,
            narrowBitmap,
            in: textFrame,
            canvasBounds: wideController.canvasView.bounds
        )

        // Then
        #expect(differenceCount > 20)
    }

    @Test("live marked text를 effective content의 TextKit2 text drawing에 반영한다")
    func drawsMarkedText() throws {
        // Given
        let controller = makeTextController(
            text: "AB",
            selection: .caret(blockID: "text", offset: 1),
            chromeRenderer: PoisoningBlockChromeRenderer()
        )
        prepare(controller)
        let baseline = try renderBitmap(for: controller, prepareBeforeDrawing: false)

        // When
        controller.setMarkedTextFromNativeSurface(
            "M",
            selectedRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let marked = try renderBitmap(for: controller, prepareBeforeDrawing: false)
        let textFrame = try #require(
            controller.snapshot?.visibleBlocks.first?.textRender.frame
        )
        let effectiveText = controller.snapshot?.activeTextInput?
            .renderDescriptor.measureRequest.text
        let differenceCount = try countPixelDifferences(
            baseline,
            marked,
            in: textFrame,
            canvasBounds: controller.canvasView.bounds
        )

        // Then
        #expect(effectiveText == "AMB")
        #expect(differenceCount > 5)
    }

    @Test(
        "host chrome hook의 graphics state가 다음 native drawing으로 누출되지 않는다"
    )
    func isolatesGraphicsState() throws {
        // Given
        let renderer = RecordingPoisoningBlockChromeRenderer()
        let controller = makeController(
            blocks: [
                EditorBlockInput(id: "a", content: BlockContent(text: "First")),
                EditorBlockInput(id: "b", content: BlockContent(text: "Second")),
            ],
            selection: .inactive,
            chromeRenderer: renderer
        )
        prepare(controller)

        // When
        _ = try drawOnce(controller)
        let first = try #require(renderer.records.first)
        let second = try #require(renderer.records.dropFirst().first)

        // Then
        #expect(renderer.records.map(\.blockID) == ["a", "b"])
        #expect(second.transform == first.transform)
        #expect(first.clipBounds == first.blockFrame)
        #expect(second.clipBounds == second.blockFrame)
    }
}

@MainActor
private final class RecordingBlockChromeRenderer: AppKitBlockChromeRenderer {
    struct Record {
        let id: BlockID
        let kind: BlockKind
        let markerKind: BlockMarkerKind
        let depth: Int
        let frame: CGRect
        let fontSize: Double
        let isActive: Bool
        let isSelected: Bool
    }

    var records: [Record] = []
    var onDrawChrome: ((BlockID) -> Void)?

    func drawChrome(_ context: AppKitBlockChromeRenderContext) {
        records.append(
            Record(
                id: context.blockID,
                kind: context.kind,
                markerKind: context.markerKind,
                depth: context.depth,
                frame: context.blockFrame,
                fontSize: context.style.fontSize,
                isActive: context.isActive,
                isSelected: context.isSelected
            )
        )
        onDrawChrome?(context.blockID)
        AppKitDefaultBlockChromeRenderer().drawChrome(context)
    }
}

@MainActor
private struct PoisoningBlockChromeRenderer: AppKitBlockChromeRenderer {
    func drawChrome(_ context: AppKitBlockChromeRenderContext) {
        let frame = context.blockFrame
        context.graphicsContext.setFillColor(NSColor.systemPink.cgColor)
        context.graphicsContext.fill(frame)
        poison(context.graphicsContext)
    }
}

@MainActor
private struct OverflowingBlockChromeRenderer: AppKitBlockChromeRenderer {
    func drawChrome(_ context: AppKitBlockChromeRenderContext) {
        context.graphicsContext.setFillColor(NSColor.systemPink.cgColor)
        context.graphicsContext.fill(
            CGRect(x: -1_000, y: -1_000, width: 2_000, height: 2_000)
        )
    }
}

@MainActor
private final class RecordingPoisoningBlockChromeRenderer: AppKitBlockChromeRenderer {
    struct Record {
        let blockID: BlockID
        let blockFrame: CGRect
        let transform: CGAffineTransform
        let clipBounds: CGRect
    }

    var records: [Record] = []

    func drawChrome(_ context: AppKitBlockChromeRenderContext) {
        records.append(
            Record(
                blockID: context.blockID,
                blockFrame: context.blockFrame,
                transform: context.graphicsContext.ctm,
                clipBounds: context.graphicsContext.boundingBoxOfClipPath
            )
        )
        poison(context.graphicsContext)
    }
}

private func poison(_ context: CGContext) {
    context.translateBy(x: 200, y: 200)
    context.setAlpha(0)
    context.clip(to: .zero)
}

@MainActor
private func makeController(
    blocks: [EditorBlockInput],
    selection: EditorSelection,
    chromeRenderer: any AppKitBlockChromeRenderer
) -> AppKitEditorViewController {
    AppKitEditorViewController(
        blocks: blocks,
        selection: selection,
        blockChromeRenderer: chromeRenderer
    )
}

@MainActor
private func makeTextController(
    text: String,
    selection: EditorSelection,
    chromeRenderer: any AppKitBlockChromeRenderer
) -> AppKitEditorViewController {
    makeController(
        blocks: [EditorBlockInput(id: "text", content: BlockContent(text: text))],
        selection: selection,
        chromeRenderer: chromeRenderer
    )
}

@MainActor
private func prepare(_ controller: AppKitEditorViewController) {
    controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
    controller.view.layoutSubtreeIfNeeded()
    controller.renderAndSyncSurface(makeFirstResponder: false)
}

@MainActor
private func renderBitmap(
    for controller: AppKitEditorViewController,
    prepareBeforeDrawing: Bool = true
) throws -> NSBitmapImageRep {
    if prepareBeforeDrawing {
        prepare(controller)
    }
    return try drawOnce(controller)
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

private func countPixelDifferences(
    _ lhs: NSBitmapImageRep,
    _ rhs: NSBitmapImageRep,
    in frame: EditorRect,
    canvasBounds: NSRect
) throws -> Int {
    try #require(lhs.pixelsWide == rhs.pixelsWide)
    try #require(lhs.pixelsHigh == rhs.pixelsHigh)
    let xRange = pixelXRange(for: frame, canvasBounds: canvasBounds, bitmap: lhs)
    var count = 0
    for y in 0..<lhs.pixelsHigh {
        for x in xRange {
            guard
                let lhsColor = lhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                let rhsColor = rhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                differs(lhsColor, from: rhsColor)
            else { continue }
            count += 1
        }
    }
    return count
}

private func pixelXRange(
    for frame: EditorRect,
    canvasBounds: NSRect,
    bitmap: NSBitmapImageRep
) -> Range<Int> {
    let scale = Double(bitmap.pixelsWide) / max(1, canvasBounds.width)
    let lowerBound = max(
        0,
        Int(((frame.minX - canvasBounds.minX) * scale).rounded(.down))
    )
    let upperBound = min(
        bitmap.pixelsWide,
        Int(((frame.maxX - canvasBounds.minX) * scale).rounded(.up))
    )
    return lowerBound..<max(lowerBound, upperBound)
}

private func differs(_ lhs: NSColor, from rhs: NSColor) -> Bool {
    abs(lhs.redComponent - rhs.redComponent) > 0.05
        || abs(lhs.greenComponent - rhs.greenComponent) > 0.05
        || abs(lhs.blueComponent - rhs.blueComponent) > 0.05
        || abs(lhs.alphaComponent - rhs.alphaComponent) > 0.05
}
