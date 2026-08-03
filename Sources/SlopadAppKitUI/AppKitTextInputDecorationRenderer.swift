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
        let request = descriptor.renderDescriptor.measureRequest
        let position = TextPosition(
            blockID: request.blockID,
            offset: descriptor.focusOffset,
            affinity: descriptor.focusAffinity
        )
        guard
            let localRect = textLayouter.caretRect(
                for: position,
                navigationContext: descriptor.navigationContext,
                in: descriptor.renderDescriptor
            )
        else { return nil }
        return documentRect(localRect, in: descriptor.renderDescriptor)
    }

    private func selectionRects(
        for descriptor: EditorSessionActiveTextInputDescriptor
    ) -> [CGRect] {
        textLayouter.selectionRects(
            for: descriptor.selectedRange,
            in: descriptor.renderDescriptor
        ).map {
            documentRect($0, in: descriptor.renderDescriptor)
        }
    }

    private func documentRect(
        _ localRect: EditorRect,
        in descriptor: EditorTextRenderDescriptor
    ) -> CGRect {
        let localFrame = textLayouter.textFrame(for: descriptor, measuredHeight: nil)
        return CGRect(
            x: CGFloat(localRect.x + descriptor.frame.x - localFrame.x),
            y: CGFloat(localRect.y + descriptor.frame.y - localFrame.y),
            width: CGFloat(localRect.width),
            height: CGFloat(localRect.height)
        )
    }
}
