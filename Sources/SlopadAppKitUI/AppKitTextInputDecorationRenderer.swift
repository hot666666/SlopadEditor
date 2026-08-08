import AppKit
import CoreGraphics
import SlopadAppKitTextKit
import SlopadEngine

// MARK: - AppKitTextInputDecorationRenderer

@MainActor
struct AppKitTextInputDecorationRenderer {
    // MARK: - Private Types

    private enum UX {
        static let activeSelectionAlpha: CGFloat = 0.35
        static let caretMinimumWidth: CGFloat = 1
        static let caretMinimumHeight: CGFloat = 14
    }

    // MARK: - Dependencies

    private let textLayouter: TextKitBlockTextLayouter

    // MARK: - Init

    init(textLayouter: TextKitBlockTextLayouter) {
        self.textLayouter = textLayouter
    }

    // MARK: - Drawing

    func draw(
        _ descriptor: EditorSessionActiveTextInputDescriptor,
        graphicsContext: CGContext
    ) {
        graphicsContext.saveGState()
        defer { graphicsContext.restoreGState() }

        NSColor.selectedTextBackgroundColor.withAlphaComponent(UX.activeSelectionAlpha).setFill()
        for rect in selectionRects(for: descriptor) where rect.width > 0 {
            rect.fill()
        }

        guard let caretRect = caretRect(for: descriptor) else { return }
        NSColor.controlAccentColor.setFill()
        CGRect(
            x: caretRect.minX,
            y: caretRect.minY,
            width: max(UX.caretMinimumWidth, caretRect.width),
            height: max(UX.caretMinimumHeight, caretRect.height)
        ).fill()
    }

    // MARK: - Geometry

    private func caretRect(
        for descriptor: EditorSessionActiveTextInputDescriptor
    ) -> CGRect? {
        descriptor.caretRect.map(CGRect.init)
    }

    private func selectionRects(
        for descriptor: EditorSessionActiveTextInputDescriptor
    ) -> [CGRect] {
        descriptor.selectionRects.map(CGRect.init)
    }
}
