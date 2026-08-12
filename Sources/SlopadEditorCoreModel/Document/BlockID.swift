import Foundation

// MARK: - BlockID

public struct BlockID: Hashable, Codable, Sendable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public var rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }
}
