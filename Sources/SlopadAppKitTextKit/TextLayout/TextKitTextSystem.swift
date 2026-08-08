import SlopadCoreModel

// MARK: - TextKitTextSystem

/// A layouter and a renderer that share one TextKit layout context.
///
/// Measurement, geometry, and drawing must agree on the same shaped text — that is the whole
/// premise of ADR 0003's single coherent backend. Constructing the two independently gave
/// each its own prepared state, so agreement held only because both were handed equal
/// requests. Sharing the context makes it structural: there is one set of TextKit objects and
/// one prepared slot, so they cannot be loaded with different blocks.
///
/// It also removes repeated work. A frame draws a block and then asks for its caret; with
/// separate contexts the second call re-prepared what the first had just prepared.
///
/// The context stays internal. A host gets the pair, never the TextKit objects behind it.
public struct TextKitTextSystem: Sendable {
    public let layouter: TextKitBlockTextLayouter
    public let renderer: TextKitBlockRenderer

    public init(style: TextKitEditorStyle = TextKitEditorStyle()) {
        let context = TextKitLayoutContext()
        layouter = TextKitBlockTextLayouter(style: style, layoutContext: context)
        renderer = TextKitBlockRenderer(style: style, layoutContext: context)
        self.context = context
    }

    /// Drops derived state that a style or backend change invalidates.
    public func invalidateCaches() {
        context.invalidateCaches()
    }

    private let context: TextKitLayoutContext
}
