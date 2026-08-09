// MARK: - TextRange

public struct TextRange: Hashable, Codable, Sendable {
    public var lowerBound: Int
    public var upperBound: Int

    public init(_ lowerBound: Int, _ upperBound: Int) {
        precondition(lowerBound >= 0, "TextRange lowerBound must be non-negative")
        precondition(upperBound >= lowerBound, "TextRange upperBound must be >= lowerBound")
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public static func point(_ offset: Int) -> TextRange {
        TextRange(offset, offset)
    }

    public var length: Int {
        upperBound - lowerBound
    }

    public var isEmpty: Bool {
        lowerBound == upperBound
    }

    public func contains(_ offset: Int) -> Bool {
        lowerBound <= offset && offset < upperBound
    }

    public func contains(_ range: TextRange) -> Bool {
        lowerBound <= range.lowerBound && range.upperBound <= upperBound
    }

    public func intersects(_ other: TextRange) -> Bool {
        lowerBound < other.upperBound && other.lowerBound < upperBound
    }

    public func isAdjacent(to other: TextRange) -> Bool {
        upperBound == other.lowerBound || other.upperBound == lowerBound
    }

    public func clamped(to count: Int) -> TextRange {
        let lower = Swift.max(0, Swift.min(lowerBound, count))
        let upper = Swift.max(lower, Swift.min(upperBound, count))
        return TextRange(lower, upper)
    }

    package func shifted(by delta: Int) -> TextRange {
        TextRange(lowerBound + delta, upperBound + delta)
    }
}
