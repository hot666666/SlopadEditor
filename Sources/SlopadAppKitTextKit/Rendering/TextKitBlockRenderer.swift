import CoreGraphics
import SlopadCoreModel

// MARK: - TextKitBlockRenderer

public struct TextKitBlockRenderer: Sendable {
    public init(style: TextKitEditorStyle = TextKitEditorStyle()) {
        self.init(style: style, layoutContext: TextKitLayoutContext())
    }

    public func draw(
        _ request: BlockMeasureRequest,
        in frame: CGRect,
        context: CGContext
    ) {
        layoutContext.draw(
            request,
            in: frame,
            style: style,
            context: context
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
