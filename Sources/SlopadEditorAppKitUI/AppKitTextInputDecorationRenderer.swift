import AppKit
import CoreGraphics
import SlopadEditorEngine

// MARK: - AppKitTextInputDecorationRenderer

@MainActor
struct AppKitTextInputDecorationRenderer {
    // MARK: - Private Types

    private enum UX {
        static let activeSelectionAlpha: CGFloat = 0.35
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
    }

    func draw(
        _ presentation: EditorSelectionPresentation,
        graphicsContext: CGContext
    ) {
        graphicsContext.saveGState()
        defer { graphicsContext.restoreGState() }

        NSColor.selectedTextBackgroundColor.withAlphaComponent(UX.activeSelectionAlpha).setFill()
        for fragment in presentation.visibleTextSelections {
            if let tint = fragment.blockTintRect {
                CGRect(editorRect: tint).fill()
            }
            for rect in fragment.rects where rect.width > 0 {
                CGRect(editorRect: rect).fill()
            }
        }
    }

    // MARK: - Geometry

    private func selectionRects(
        for descriptor: EditorSessionActiveTextInputDescriptor
    ) -> [CGRect] {
        descriptor.selectionRects.map(CGRect.init)
    }
}
