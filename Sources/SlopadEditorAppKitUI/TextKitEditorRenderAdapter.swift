import CoreGraphics
import SlopadEditorAppKitTextKit
import SlopadEditorEngine

// MARK: - Engine Render Descriptor Adaptation

// The geometry overloads that used to live here are gone. Caret and selection rectangles now
// arrive on the Session snapshot already in document coordinates, so the adapter has nothing
// to ask the backend for. Drawing is the one thing left that still takes a descriptor.

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
