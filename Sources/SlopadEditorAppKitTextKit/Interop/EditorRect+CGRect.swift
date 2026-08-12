import CoreGraphics
import SlopadCoreModel

// MARK: - EditorRect CGRect

extension CGRect {
    public init(editorRect rect: EditorRect) {
        self.init(
            x: CGFloat(rect.x),
            y: CGFloat(rect.y),
            width: CGFloat(rect.width),
            height: CGFloat(rect.height)
        )
    }
}

extension EditorRect {
    public init(cgRect rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }
}
