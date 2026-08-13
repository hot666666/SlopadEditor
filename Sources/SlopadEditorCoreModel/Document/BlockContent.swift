// MARK: - BlockContent

public struct BlockContent: Hashable, Codable, Sendable {
    public struct InlineMark: Hashable, Codable, Sendable {
        /// Format-neutral inline meaning.
        ///
        /// The core owns this vocabulary. A format adapter maps its syntax onto these cases
        /// and reports what it cannot express as a diagnostic; a text backend interprets
        /// them as visual effects. Neither may extend the set — that is a core decision.
        ///
        /// The names are semantic rather than presentational for the same reason HTML
        /// distinguishes `<strong>` from `<b>`: a neutral vocabulary cannot be stated in the
        /// terms of one renderer.
        public enum Kind: Hashable, Codable, Sendable, Comparable {
            case strong
            case emphasis
            case code
            case strikethrough
            case link(destination: String)

            /// Identifies the case while ignoring any associated value.
            ///
            /// Removal matches on this rather than on the whole value, so "remove the link
            /// here" does not require knowing where the link points.
            package var caseIdentity: CaseIdentity {
                switch self {
                case .strong: .strong
                case .emphasis: .emphasis
                case .code: .code
                case .strikethrough: .strikethrough
                case .link: .link
                }
            }

            package enum CaseIdentity: Hashable, Sendable {
                case strong
                case emphasis
                case code
                case strikethrough
                case link
            }

            public static func < (lhs: Kind, rhs: Kind) -> Bool {
                func sortKey(_ kind: Kind) -> String {
                    switch kind {
                    case .strong: "strong"
                    case .emphasis: "emphasis"
                    case .code: "code"
                    case .strikethrough: "strikethrough"
                    case .link(let destination): "link:\(destination)"
                    }
                }
                return sortKey(lhs) < sortKey(rhs)
            }

            // MARK: - Coding

            // Written by hand rather than synthesized so that documents encoded before
            // `.strong`/`.emphasis` were named that way still decode. The emitted shape is
            // identical to what synthesis produced — `{"strong":{}}`, and
            // `{"link":{"destination":…}}` — so only the reading side is widened.

            private enum CodingKeys: String, CodingKey {
                case strong
                case emphasis
                case code
                case strikethrough
                case link
                /// Superseded by ``strong``. Decoded, never written.
                case bold
                /// Superseded by ``emphasis``. Decoded, never written.
                case italic
            }

            private enum LinkCodingKeys: String, CodingKey {
                case destination
            }

            private enum EmptyCodingKeys: CodingKey {}

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                guard container.allKeys.count == 1, let key = container.allKeys.first else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: container.codingPath,
                            debugDescription:
                                "Expected exactly one inline mark kind, found \(container.allKeys.count)."
                        ))
                }
                switch key {
                case .strong, .bold:
                    self = .strong
                case .emphasis, .italic:
                    self = .emphasis
                case .code:
                    self = .code
                case .strikethrough:
                    self = .strikethrough
                case .link:
                    let nested = try container.nestedContainer(
                        keyedBy: LinkCodingKeys.self, forKey: .link)
                    self = .link(destination: try nested.decode(String.self, forKey: .destination))
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .strong:
                    _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .strong)
                case .emphasis:
                    _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .emphasis)
                case .code:
                    _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .code)
                case .strikethrough:
                    _ = container.nestedContainer(
                        keyedBy: EmptyCodingKeys.self, forKey: .strikethrough)
                case .link(let destination):
                    var nested = container.nestedContainer(
                        keyedBy: LinkCodingKeys.self, forKey: .link)
                    try nested.encode(destination, forKey: .destination)
                }
            }
        }

        public var kind: Kind
        public var range: TextRange

        public init(kind: Kind, range: TextRange) {
            self.kind = kind
            self.range = range
        }
    }

    public struct InlineRun: Hashable, Sendable {
        public var range: TextRange
        public var text: String
        public var marks: Set<InlineMark.Kind>

        public init(range: TextRange, text: String, marks: Set<InlineMark.Kind>) {
            self.range = range
            self.text = text
            self.marks = marks
        }
    }

    public var text: String
    public var marks: [InlineMark]

    public init(text: String = "", marks: [InlineMark] = []) {
        self.init(text: text, marks: marks, revision: 0)
    }

    package init(
        validatingCanonicalText text: String,
        marks: [InlineMark]
    ) throws(CanonicalBlockContentValidationError) {
        guard marks == BlockContent.normalizedMarks(marks, textLength: text.count) else {
            throw .noncanonicalMarks
        }
        self.text = text
        self.marks = marks
        revision = 0
    }

    public var length: Int {
        text.count
    }

    public var inlineRuns: [InlineRun] {
        BlockContent.inlineRuns(text: text, marks: marks)
    }

    public static func == (lhs: BlockContent, rhs: BlockContent) -> Bool {
        lhs.text == rhs.text && lhs.marks == rhs.marks
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(marks)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .text)
        let marks = try container.decodeIfPresent([InlineMark].self, forKey: .marks) ?? []
        self.init(text: text, marks: marks, revision: 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(marks, forKey: .marks)
    }

    // MARK: - Package Normalization

    package var revision: Int

    var isCanonical: Bool {
        marks == BlockContent.normalizedMarks(marks, textLength: text.count)
    }

    init(text: String = "", marks: [InlineMark] = [], revision: Int) {
        self.text = text
        self.marks = BlockContent.normalizedMarks(marks, textLength: text.count)
        self.revision = revision
    }

    static func normalizedMarks(_ marks: [InlineMark], textLength: Int) -> [InlineMark] {
        let clamped = marks.compactMap { mark -> InlineMark? in
            let range = mark.range.clamped(to: textLength)
            guard !range.isEmpty else { return nil }
            return InlineMark(kind: mark.kind, range: range)
        }

        let grouped = Dictionary(grouping: clamped, by: \.kind)
        var normalized: [InlineMark] = []
        for (kind, group) in grouped {
            let sorted = group.sorted {
                if $0.range.lowerBound == $1.range.lowerBound {
                    $0.range.upperBound < $1.range.upperBound
                } else {
                    $0.range.lowerBound < $1.range.lowerBound
                }
            }
            var current: TextRange?
            for mark in sorted {
                guard var range = current else {
                    current = mark.range
                    continue
                }
                if range.intersects(mark.range) || range.isAdjacent(to: mark.range) {
                    range.upperBound = max(range.upperBound, mark.range.upperBound)
                    current = range
                } else {
                    normalized.append(InlineMark(kind: kind, range: range))
                    current = mark.range
                }
            }
            if let current {
                normalized.append(InlineMark(kind: kind, range: current))
            }
        }

        return normalized.sorted {
            if $0.range.lowerBound != $1.range.lowerBound {
                return $0.range.lowerBound < $1.range.lowerBound
            }
            if $0.range.upperBound != $1.range.upperBound {
                return $0.range.upperBound < $1.range.upperBound
            }
            return $0.kind < $1.kind
        }
    }

    static func inlineRuns(text: String, marks: [InlineMark]) -> [InlineRun] {
        let length = text.count
        guard length > 0 else { return [] }
        var boundaries: Set<Int> = [0, length]
        for mark in normalizedMarks(marks, textLength: length) {
            boundaries.insert(mark.range.lowerBound)
            boundaries.insert(mark.range.upperBound)
        }
        let sortedBoundaries = boundaries.sorted()
        var runs: [InlineRun] = []
        for index in 0..<(sortedBoundaries.count - 1) {
            let lower = sortedBoundaries[index]
            let upper = sortedBoundaries[index + 1]
            guard lower < upper else { continue }
            let range = TextRange(lower, upper)
            let active = Set(
                marks.compactMap { mark in
                    mark.range.contains(range) ? mark.kind : nil
                })
            runs.append(InlineRun(range: range, text: text.substring(in: range), marks: active))
        }
        return runs
    }

    // MARK: - Coding Keys

    private enum CodingKeys: String, CodingKey {
        case text
        case marks
    }
}

package enum CanonicalBlockContentValidationError: Error, Hashable, Sendable {
    case noncanonicalMarks
}
