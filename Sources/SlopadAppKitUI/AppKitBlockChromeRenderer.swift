import AppKit
import CoreGraphics
import SlopadAppKitTextKit
import SlopadEngine

// MARK: - AppKitBlockChromeRenderer

/// Draws host-defined block chrome without replacing native text and input feedback.
@MainActor
public protocol AppKitBlockChromeRenderer {
    /// Draws backgrounds, borders, gutters, markers, or equivalent block decoration.
    ///
    /// The adapter clips the graphics context to the block frame, restores graphics state
    /// after the call, and draws its TextKit2-backed text and input feedback in later passes.
    func drawChrome(_ context: AppKitBlockChromeRenderContext)
}

// MARK: - AppKitBlockChromeRenderContext

/// Read-only facts for one block's chrome pass in canvas/document coordinates.
public struct AppKitBlockChromeRenderContext {
    public let blockID: BlockID
    public let kind: BlockKind
    public let markerKind: BlockMarkerKind
    public let depth: Int
    /// The block's frame in canvas/document coordinates and the maximum paint region.
    public let blockFrame: CGRect
    public let style: AppKitEditorStyle
    /// A context clipped by both the current dirty region and ``blockFrame``.
    ///
    /// The adapter saves and restores its graphics state around `drawChrome(_:)`.
    public let graphicsContext: CGContext
    public let isActive: Bool
    public let isSelected: Bool

    init(
        blockID: BlockID,
        kind: BlockKind,
        markerKind: BlockMarkerKind,
        depth: Int,
        blockFrame: CGRect,
        style: AppKitEditorStyle,
        graphicsContext: CGContext,
        isActive: Bool,
        isSelected: Bool
    ) {
        self.blockID = blockID
        self.kind = kind
        self.markerKind = markerKind
        self.depth = depth
        self.blockFrame = blockFrame
        self.style = style
        self.graphicsContext = graphicsContext
        self.isActive = isActive
        self.isSelected = isSelected
    }
}

// MARK: - AppKitDefaultBlockChromeRenderer

public struct AppKitDefaultBlockChromeRenderer: AppKitBlockChromeRenderer {
    // MARK: - Private Types

    private enum UX {
        static let activeBackgroundAlpha: CGFloat = 0.07
        static let selectedBackgroundAlpha: CGFloat = 0.16
        static let selectedBorderAlpha: CGFloat = 0.65
        static let selectedBorderInset: CGFloat = 1
        static let selectedBorderWidth: CGFloat = 1.5
        static let gutterSeparatorAlpha: CGFloat = 0.25
        static let gutterSeparatorWidth: CGFloat = 1
        static let gutterIconSize: CGFloat = 16
        static let gutterIconTopPadding: CGFloat = 9
        static let gutterFallbackInset: CGFloat = 4
        static let gutterSymbolFraction: CGFloat = 0.82
        static let gutterTextFontSize: CGFloat = 11
    }

    // MARK: - Init

    public init() {}

    // MARK: - Public

    public func drawChrome(_ context: AppKitBlockChromeRenderContext) {
        drawBlockBackground(context.blockFrame, context: context)
        drawGutter(frame: context.blockFrame, context: context)
    }

    // MARK: - Block Drawing

    private func drawBlockBackground(
        _ frame: CGRect,
        context: AppKitBlockChromeRenderContext
    ) {
        let blockBackground: NSColor
        if context.isActive {
            blockBackground = NSColor.controlAccentColor.withAlphaComponent(
                UX.activeBackgroundAlpha
            )
        } else if context.isSelected {
            blockBackground = NSColor.selectedContentBackgroundColor
                .withAlphaComponent(UX.selectedBackgroundAlpha)
        } else {
            blockBackground = .clear
        }
        blockBackground.setFill()
        frame.fill()

        if context.isSelected {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(UX.selectedBorderAlpha)
                .setStroke()
            let path = NSBezierPath(
                rect: frame.insetBy(
                    dx: UX.selectedBorderInset,
                    dy: UX.selectedBorderInset
                )
            )
            path.lineWidth = UX.selectedBorderWidth
            path.stroke()
        }
    }

    private func drawGutter(
        frame: CGRect,
        context: AppKitBlockChromeRenderContext
    ) {
        let gutterRect = CGRect(
            x: 0,
            y: frame.minY,
            width: context.style.gutterWidth,
            height: frame.height
        )
        NSColor.separatorColor.withAlphaComponent(UX.gutterSeparatorAlpha).setFill()
        CGRect(
            x: gutterRect.maxX - UX.gutterSeparatorWidth,
            y: gutterRect.minY,
            width: UX.gutterSeparatorWidth,
            height: gutterRect.height
        ).fill()
        drawGutterMarker(
            markerKind: context.markerKind,
            kind: context.kind,
            in: gutterRect
        )
    }

    // MARK: - Gutter Drawing

    private func drawGutterMarker(
        markerKind: BlockMarkerKind,
        kind: BlockKind,
        in rect: CGRect
    ) {
        if case .orderedListItem(let number) = markerKind {
            drawGutterText("\(number).", in: rect)
            return
        }

        let symbolName: String
        switch markerKind {
        case .unorderedListItem:
            symbolName = "list.bullet"
        case .todo(let checked):
            symbolName = checked ? "checkmark.square" : "square"
        case .none:
            symbolName = gutterSymbolName(for: kind)
        case .orderedListItem:
            symbolName = "list.number"
        }

        drawGutterSymbol(symbolName, in: rect)
    }

    private func gutterSymbolName(for kind: BlockKind) -> String {
        switch kind {
        case .heading:
            return "h.square"
        case .unorderedListItem:
            return "list.bullet"
        case .orderedListItem:
            return "list.number"
        case .todo(let checked):
            return checked ? "checkmark.square" : "square"
        case .quote:
            return "quote.opening"
        case .codeBlock:
            return "curlybraces"
        case .divider:
            return "minus"
        case .paragraph:
            return "line.3.horizontal"
        }
    }

    private func drawGutterSymbol(_ symbolName: String, in rect: CGRect) {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        let imageRect = CGRect(
            x: rect.midX - UX.gutterIconSize / 2,
            y: rect.minY + UX.gutterIconTopPadding,
            width: UX.gutterIconSize,
            height: UX.gutterIconSize
        )
        NSColor.secondaryLabelColor.set()
        if let image {
            image.draw(
                in: imageRect,
                from: .zero,
                operation: .sourceOver,
                fraction: UX.gutterSymbolFraction
            )
        } else {
            NSBezierPath(
                ovalIn: imageRect.insetBy(
                    dx: UX.gutterFallbackInset,
                    dy: UX.gutterFallbackInset
                )
            ).fill()
        }
    }

    private func drawGutterText(_ text: String, in rect: CGRect) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: UX.gutterTextFontSize,
                weight: .medium
            ),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle,
        ]
        text.draw(
            in: CGRect(
                x: rect.minX,
                y: rect.minY + UX.gutterIconTopPadding,
                width: rect.width,
                height: UX.gutterIconSize
            ),
            withAttributes: attributes
        )
    }
}
