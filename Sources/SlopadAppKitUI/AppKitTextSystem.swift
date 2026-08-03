import SlopadAppKitTextKit

// MARK: - AppKitTextSystem

/// One coherent TextKit2 geometry and drawing system owned by the AppKit adapter.
@MainActor
struct AppKitTextSystem {
    let style: AppKitEditorStyle
    let textLayouter: TextKitBlockTextLayouter
    let textRenderer: TextKitBlockRenderer
    let textInputDecorationRenderer: AppKitTextInputDecorationRenderer

    init(style: AppKitEditorStyle) {
        let textLayouter = TextKitBlockTextLayouter(style: style)
        self.style = style
        self.textLayouter = textLayouter
        self.textRenderer = TextKitBlockRenderer(style: style)
        self.textInputDecorationRenderer = AppKitTextInputDecorationRenderer(
            textLayouter: textLayouter
        )
    }
}
