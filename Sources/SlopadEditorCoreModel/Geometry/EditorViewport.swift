// MARK: - EditorViewport

public struct EditorViewport: Hashable, Sendable {
    public var width: Double
    public var scrollY: Double
    public var height: Double

    public init(width: Double, scrollY: Double, height: Double) {
        self.width = width
        self.scrollY = scrollY
        self.height = height
    }

    package var widthRevision: Int {
        Int(truncatingIfNeeded: width.bitPattern)
    }

    package var visibleRect: EditorRect {
        EditorRect(x: 0, y: scrollY, width: max(0, width), height: max(0, height))
    }
}
