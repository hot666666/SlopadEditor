// MARK: - TextPosition

public struct TextPosition: Hashable, Codable, Sendable {
    public var blockID: BlockID
    public var offset: Int
    public var affinity: TextAffinity

    public init(
        blockID: BlockID,
        offset: Int,
        affinity: TextAffinity = .downstream
    ) {
        self.blockID = blockID
        self.offset = offset
        self.affinity = affinity
    }

    private enum CodingKeys: String, CodingKey {
        case blockID
        case offset
        case affinity
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockID = try container.decode(BlockID.self, forKey: .blockID)
        offset = try container.decode(Int.self, forKey: .offset)
        affinity = try container.decodeIfPresent(TextAffinity.self, forKey: .affinity)
            ?? .downstream
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blockID, forKey: .blockID)
        try container.encode(offset, forKey: .offset)
        if affinity != .downstream {
            try container.encode(affinity, forKey: .affinity)
        }
    }
}
