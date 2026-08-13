// MARK: - BlockMeasurement

public struct BlockMeasurement: Hashable, Sendable {
    public let height: Double
    public let firstBaseline: Double?

    public init(height: Double, firstBaseline: Double? = nil) {
        self.height = height
        self.firstBaseline = firstBaseline
    }
}
