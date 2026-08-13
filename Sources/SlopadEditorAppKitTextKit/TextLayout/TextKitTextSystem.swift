import SlopadEditorCoreModel

// MARK: - TextKitTextSystem

/// A layouter and a renderer that share one TextKit layout context.
///
/// Measurement, geometry, and drawing must agree on the same shaped text — that is the whole
/// premise of ADR 0003's single coherent backend. Constructing the two independently gave
/// each its own prepared state, so agreement held only because both were handed equal
/// requests. Sharing the context makes it structural: there is one set of TextKit objects and
/// one bounded prepared-layout store shared across both roles.
///
/// The context stays internal. A host gets the pair, never the TextKit objects behind it.
public struct TextKitTextSystem: Sendable {
    public let layouter: TextKitBlockTextLayouter
    public let renderer: TextKitBlockRenderer
    private let layoutContext: TextKitLayoutContext

    public init(style: TextKitEditorStyle = TextKitEditorStyle()) {
        let context = TextKitLayoutContext()
        layoutContext = context
        layouter = TextKitBlockTextLayouter(style: style, layoutContext: context)
        renderer = TextKitBlockRenderer(style: style, layoutContext: context)
    }

    init(
        style: TextKitEditorStyle = TextKitEditorStyle(),
        preparedLayoutPolicy: TextKitPreparedLayoutStorePolicy
    ) {
        let context = TextKitLayoutContext(policy: preparedLayoutPolicy)
        layoutContext = context
        layouter = TextKitBlockTextLayouter(style: style, layoutContext: context)
        renderer = TextKitBlockRenderer(style: style, layoutContext: context)
    }

    package func setActivePreparedLayoutBlockID(_ blockID: BlockID?) {
        layoutContext.setActiveBlockID(blockID)
    }

    package func removeAllPreparedLayouts() {
        layoutContext.removeAllPreparedLayouts()
    }

    package func handlePreparedLayoutMemoryPressure(
        _ pressure: TextKitPreparedLayoutMemoryPressure
    ) {
        layoutContext.handleMemoryPressure(pressure)
    }
}
