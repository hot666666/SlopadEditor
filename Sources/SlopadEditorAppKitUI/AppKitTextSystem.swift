import SlopadEditorAppKitTextKit
import SlopadEditorEngine

// MARK: - AppKitTextSystem

/// One coherent TextKit2 geometry and drawing system owned by the AppKit adapter.
@MainActor
struct AppKitTextSystem {
    let style: AppKitEditorStyle
    let textLayouter: TextKitBlockTextLayouter
    let textRenderer: TextKitBlockRenderer
    let textInputDecorationRenderer: AppKitTextInputDecorationRenderer
    private let textKitSystem: TextKitTextSystem

    init(style: AppKitEditorStyle) {
        // One shared context, not one per role — see `TextKitTextSystem`.
        let system = TextKitTextSystem(style: style)
        let textLayouter = system.layouter
        self.style = style
        self.textKitSystem = system
        self.textLayouter = textLayouter
        self.textRenderer = system.renderer
        self.textInputDecorationRenderer = AppKitTextInputDecorationRenderer()
    }

    func setActivePreparedLayoutBlockID(_ blockID: BlockID?) {
        textKitSystem.setActivePreparedLayoutBlockID(blockID)
    }

    func removeAllPreparedLayouts() {
        textKitSystem.removeAllPreparedLayouts()
    }

    func handlePreparedLayoutMemoryPressure(
        _ pressure: TextKitPreparedLayoutMemoryPressure
    ) {
        textKitSystem.handlePreparedLayoutMemoryPressure(pressure)
    }
}
