// MARK: - EditorRect

public struct EditorRect: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    package var minX: Double { x }
    package var minY: Double { y }
    package var maxX: Double { x + width }
    package var maxY: Double { y + height }

    package var isEmpty: Bool {
        width <= 0 || height <= 0
    }

    package var midX: Double { x + width / 2 }
    package var midY: Double { y + height / 2 }

    package func offsetBy(dx: Double, dy: Double) -> EditorRect {
        EditorRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    package func intersection(_ other: EditorRect) -> EditorRect? {
        let intersectionMinX = max(minX, other.minX)
        let intersectionMinY = max(minY, other.minY)
        let intersectionMaxX = min(maxX, other.maxX)
        let intersectionMaxY = min(maxY, other.maxY)
        let intersectionWidth = intersectionMaxX - intersectionMinX
        let intersectionHeight = intersectionMaxY - intersectionMinY

        guard intersectionWidth > 0, intersectionHeight > 0 else { return nil }
        return EditorRect(
            x: intersectionMinX,
            y: intersectionMinY,
            width: intersectionWidth,
            height: intersectionHeight
        )
    }
}
