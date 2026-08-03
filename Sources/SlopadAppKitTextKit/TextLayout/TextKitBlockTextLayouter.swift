import AppKit
import CoreGraphics
import Foundation
import SlopadCoreModel

// MARK: - TextKitBlockTextLayouter

public struct TextKitBlockTextLayouter: BlockTextLayoutProtocol, Sendable {
    public init(style: TextKitEditorStyle = TextKitEditorStyle()) {
        self.init(style: style, layoutContext: TextKitLayoutContext())
    }

    public func measure(_ request: BlockMeasureRequest) -> BlockMeasurement {
        let baseFont = TextKitAttributedStringBuilder.baseFont(for: request.kind, style: style)
        let metrics = TextKitBlockChromeMetrics.metrics(for: request.kind)
        let measuredTextHeight = layoutContext.measure(
            request,
            style: style,
            minimumHeight: CGFloat(baseFont.ascender - baseFont.descender)
        )

        return BlockMeasurement(
            height: Double(ceil(measuredTextHeight)) + metrics.verticalPadding,
            firstBaseline: metrics.topPadding + Double(baseFont.ascender)
        )
    }

    public func attributedString(for request: BlockMeasureRequest) -> NSAttributedString {
        TextKitAttributedStringBuilder.attributedString(for: request, style: style)
    }

    public func textFrame(for request: BlockMeasureRequest, measuredHeight: Double? = nil)
        -> EditorRect
    {
        let origin = style.textOrigin(depth: request.depth, kind: request.kind)
        let height = measuredHeight.map { max(1, $0 - origin.y) } ?? CGFloat.greatestFiniteMagnitude
        return EditorRect(
            x: Double(origin.x),
            y: Double(origin.y),
            width: style.textWidth(
                availableWidth: request.availableWidth,
                depth: request.depth
            ),
            height: Double(height)
        )
    }

    public func lineFragments(for request: BlockMeasureRequest) -> [LineFragmentSnapshot] {
        layoutContext.lineFragments(for: request, style: style)
    }

    public func caretRect(for position: TextPosition, in request: BlockMeasureRequest)
        -> EditorRect?
    {
        guard position.blockID == request.blockID else { return nil }
        return layoutContext.caretRect(
            position: position,
            navigationContext: nil,
            request: request,
            style: style
        ).map(EditorRect.init(cgRect:))
    }

    public func caretRect(
        for position: TextPosition,
        navigationContext: TextNavigationContext?,
        in request: BlockMeasureRequest
    ) -> EditorRect? {
        guard position.blockID == request.blockID else { return nil }
        return layoutContext.caretRect(
            position: position,
            navigationContext: navigationContext,
            request: request,
            style: style
        ).map(EditorRect.init(cgRect:))
    }

    public func selectionRects(
        for range: SlopadCoreModel.TextRange,
        in request: BlockMeasureRequest
    )
        -> [EditorRect]
    {
        layoutContext.selectionRects(for: range, request: request, style: style)
            .map(EditorRect.init(cgRect:))
    }

    public func textPosition(at point: EditorPoint, in request: BlockMeasureRequest) -> TextPosition
    {
        // Retain the legacy non-optional protocol surface. Native-aware callers should use
        // textHitTest(at:in:) so a conversion failure is not mistaken for offset zero.
        return textHitTest(at: point, in: request)?.position
            ?? TextPosition(blockID: request.blockID, offset: 0)
    }

    public func textHitTest(
        at point: EditorPoint,
        in request: BlockMeasureRequest
    ) -> TextHitTestResult? {
        layoutContext.textHitTest(
            to: CGPoint(x: point.x, y: point.y),
            request: request,
            style: style
        )
    }

    public func navigate(
        selection: TextSelection,
        context: TextNavigationContext?,
        direction: TextNavigationDirection,
        destination: TextNavigationDestination,
        extending: Bool,
        in request: BlockMeasureRequest
    ) -> TextNavigationResolution {
        layoutContext.navigate(
            selection: selection,
            context: context,
            direction: direction,
            destination: destination,
            extending: extending,
            request: request,
            style: style
        )
    }

    public func wordRange(
        containing position: TextPosition,
        in request: BlockMeasureRequest
    ) -> SlopadCoreModel.TextRange? {
        layoutContext.wordRange(containing: position, request: request, style: style)
    }

    public func deletionRange(
        for selection: TextSelection,
        direction: TextNavigationDirection,
        destination: TextNavigationDestination,
        in request: BlockMeasureRequest
    ) -> SlopadCoreModel.TextRange? {
        layoutContext.deletionRange(
            for: selection,
            direction: direction,
            destination: destination,
            request: request,
            style: style
        )
    }

    // MARK: - Internal State

    private let style: TextKitEditorStyle
    private let layoutContext: TextKitLayoutContext

    init(style: TextKitEditorStyle, layoutContext: TextKitLayoutContext) {
        self.style = style
        self.layoutContext = layoutContext
    }
}
