import CoreGraphics
import SlopadAppKitTextKit
import SlopadEngine

// MARK: - Engine Render Descriptor Adaptation

extension TextKitBlockTextLayouter {
    func textFrame(
        for descriptor: EditorTextRenderDescriptor,
        measuredHeight: Double? = nil
    ) -> EditorRect {
        textFrame(for: descriptor.measureRequest, measuredHeight: measuredHeight)
    }

    func caretRect(
        for position: TextPosition,
        navigationContext: TextNavigationContext? = nil,
        in descriptor: EditorTextRenderDescriptor
    ) -> EditorRect? {
        caretRect(
            for: position,
            navigationContext: navigationContext,
            in: descriptor.measureRequest
        )
    }

    func selectionRects(
        for range: SlopadEngine.TextRange,
        in descriptor: EditorTextRenderDescriptor
    ) -> [EditorRect] {
        selectionRects(for: range, in: descriptor.measureRequest)
    }
}

extension TextKitBlockRenderer {
    func draw(
        _ descriptor: EditorTextRenderDescriptor,
        context: CGContext
    ) {
        draw(
            descriptor.measureRequest,
            in: CGRect(editorRect: descriptor.frame),
            context: context
        )
    }
}
