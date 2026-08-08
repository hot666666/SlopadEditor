// MARK: - TextKitTextSystem

/// A layouter and a renderer that share one TextKit layout context.
///
/// Measurement, geometry, and drawing must agree on the same shaped text — that is the whole
/// premise of ADR 0003's single coherent backend. Constructing the two independently gave
/// each its own prepared state, so agreement held only because both were handed equal
/// requests. Sharing the context makes it structural: there is one set of TextKit objects and
/// one prepared slot shared across both roles.
///
/// It also permits reuse when one role immediately asks for the same prepared key as the
/// other. The bounded multi-block store tracked by #37 remains a separate change.
///
/// The context stays internal. A host gets the pair, never the TextKit objects behind it.
public struct TextKitTextSystem: Sendable {
    public let layouter: TextKitBlockTextLayouter
    public let renderer: TextKitBlockRenderer

    public init(style: TextKitEditorStyle = TextKitEditorStyle()) {
        let context = TextKitLayoutContext()
        layouter = TextKitBlockTextLayouter(style: style, layoutContext: context)
        renderer = TextKitBlockRenderer(style: style, layoutContext: context)
    }
}
