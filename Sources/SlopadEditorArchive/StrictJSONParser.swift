import Foundation

enum StrictJSONValue {
    case object(StrictJSONObject)
    case array([StrictJSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}

struct StrictJSONObject {
    private let values: [String: StrictJSONValue]

    init(_ values: [String: StrictJSONValue]) {
        self.values = values
    }

    func required(_ key: String) throws(StrictJSONError) -> StrictJSONValue {
        guard let value = values[key] else { throw .malformed }
        return value
    }

    func requiredInteger(_ key: String) throws(StrictJSONError) -> Int {
        guard case .number(let token) = try required(key), let value = Int(token) else {
            throw .malformed
        }
        return value
    }

    var keys: Set<String> { Set(values.keys) }
}

enum StrictJSONError: Error {
    case malformed
}

/// Internal safety limits for the complete decoded JSON tree. These are wire-format
/// admission limits, not performance targets. Ten thousand ordinary blocks use about
/// 80,000 values and 70,000 object members, leaving deliberate structural headroom while
/// bounding every collection and decoded-string allocation.
struct ArchiveWireBudget: Equatable {
    static let v1 = ArchiveWireBudget(
        maximumArchiveBytes: 16 * 1_024 * 1_024,
        maximumValues: 150_000,
        maximumArrayElements: 100_000,
        maximumObjectMembers: 100_000,
        maximumDecodedStringBytes: 8 * 1_024 * 1_024
    )

    let maximumArchiveBytes: Int
    let maximumValues: Int
    let maximumArrayElements: Int
    let maximumObjectMembers: Int
    let maximumDecodedStringBytes: Int
}

struct ArchiveWireBudgetTracker {
    private let budget: ArchiveWireBudget
    private var archiveBytes = 0
    private var values = 0
    private var arrayElements = 0
    private var objectMembers = 0
    private var decodedStringBytes = 0

    init(budget: ArchiveWireBudget) {
        self.budget = budget
    }

    mutating func consumeValue() throws(StrictJSONError) {
        try consume(&values, count: 1, maximum: budget.maximumValues)
    }

    mutating func consumeArchiveBytes(_ count: Int) throws(StrictJSONError) {
        try consume(&archiveBytes, count: count, maximum: budget.maximumArchiveBytes)
    }

    mutating func consumeArrayElement() throws(StrictJSONError) {
        try consume(&arrayElements, count: 1, maximum: budget.maximumArrayElements)
    }

    mutating func consumeArrayElements(_ count: Int) throws(StrictJSONError) {
        try consume(&arrayElements, count: count, maximum: budget.maximumArrayElements)
    }

    mutating func consumeObjectMember() throws(StrictJSONError) {
        try consume(&objectMembers, count: 1, maximum: budget.maximumObjectMembers)
    }

    mutating func consumeObjectMembers(_ count: Int) throws(StrictJSONError) {
        try consume(&objectMembers, count: count, maximum: budget.maximumObjectMembers)
    }

    mutating func consumeDecodedStringBytes(_ count: Int) throws(StrictJSONError) {
        try consume(
            &decodedStringBytes,
            count: count,
            maximum: budget.maximumDecodedStringBytes
        )
    }

    mutating func consumeObject(
        memberCount: Int,
        decodedKeyBytes: Int
    ) throws(StrictJSONError) {
        try consumeValue()
        try consumeObjectMembers(memberCount)
        try consumeDecodedStringBytes(decodedKeyBytes)
    }

    mutating func consumeArray() throws(StrictJSONError) {
        try consumeValue()
    }

    mutating func consumeString(decodedUTF8Bytes: Int) throws(StrictJSONError) {
        try consumeValue()
        try consumeDecodedStringBytes(decodedUTF8Bytes)
    }

    mutating func consumeScalarValue() throws(StrictJSONError) {
        try consumeValue()
    }

    private func consume(
        _ current: inout Int,
        count: Int,
        maximum: Int
    ) throws(StrictJSONError) {
        guard count >= 0, current <= maximum - count else { throw .malformed }
        current += count
    }
}

extension StrictJSONValue {
    func exactObject(keys expectedKeys: Set<String>) throws(StrictJSONError) -> StrictJSONObject {
        guard case .object(let object) = self, object.keys == expectedKeys else {
            throw .malformed
        }
        return object
    }
}

struct StrictJSONParser {
    private let bytes: UnsafeRawBufferPointer
    private var budgetTracker: ArchiveWireBudgetTracker
    private var index = 0
    private static let maximumDepth = 128

    private init(bytes: UnsafeRawBufferPointer, budget: ArchiveWireBudget) {
        self.bytes = bytes
        budgetTracker = ArchiveWireBudgetTracker(budget: budget)
    }

    static func parse(
        _ data: Data,
        budget: ArchiveWireBudget = .v1
    ) throws(StrictJSONError) -> StrictJSONValue {
        guard data.count <= budget.maximumArchiveBytes else { throw .malformed }
        do {
            return try data.withUnsafeBytes {
                (bytes: UnsafeRawBufferPointer) throws(StrictJSONError) -> StrictJSONValue in
                var parser = StrictJSONParser(bytes: bytes, budget: budget)
                parser.skipWhitespace()
                let value = try parser.parseValue(depth: 0)
                parser.skipWhitespace()
                guard parser.index == parser.bytes.count else { throw .malformed }
                return value
            }
        } catch {
            throw .malformed
        }
    }

    private mutating func parseValue(depth: Int) throws(StrictJSONError) -> StrictJSONValue {
        guard depth <= Self.maximumDepth, let byte = currentByte else { throw .malformed }
        try budgetTracker.consumeValue()
        switch byte {
        case 0x7B:
            return .object(try parseObject(depth: depth + 1))
        case 0x5B:
            return .array(try parseArray(depth: depth + 1))
        case 0x22:
            return .string(try parseString())
        case 0x74:
            try consumeLiteral("true")
            return .bool(true)
        case 0x66:
            try consumeLiteral("false")
            return .bool(false)
        case 0x6E:
            try consumeLiteral("null")
            return .null
        case 0x2D, 0x30...0x39:
            return .number(try parseNumber())
        default:
            throw .malformed
        }
    }

    private mutating func parseObject(depth: Int) throws(StrictJSONError) -> StrictJSONObject {
        try consume(0x7B)
        skipWhitespace()
        var values: [String: StrictJSONValue] = [:]
        if consumeIfPresent(0x7D) { return StrictJSONObject(values) }

        while true {
            guard currentByte == 0x22 else { throw .malformed }
            try budgetTracker.consumeObjectMember()
            let key = try parseString()
            guard values[key] == nil else { throw .malformed }
            skipWhitespace()
            try consume(0x3A)
            skipWhitespace()
            values[key] = try parseValue(depth: depth)
            skipWhitespace()
            if consumeIfPresent(0x7D) { break }
            try consume(0x2C)
            skipWhitespace()
        }
        return StrictJSONObject(values)
    }

    private mutating func parseArray(depth: Int) throws(StrictJSONError) -> [StrictJSONValue] {
        try consume(0x5B)
        skipWhitespace()
        var values: [StrictJSONValue] = []
        if consumeIfPresent(0x5D) { return values }

        while true {
            try budgetTracker.consumeArrayElement()
            values.append(try parseValue(depth: depth))
            skipWhitespace()
            if consumeIfPresent(0x5D) { break }
            try consume(0x2C)
            skipWhitespace()
        }
        return values
    }

    private mutating func parseString() throws(StrictJSONError) -> String {
        try consume(0x22)
        var result = ""
        var segmentStart = index

        while let byte = currentByte {
            if byte == 0x22 || byte == 0x5C {
                try appendUTF8Segment(from: segmentStart, to: index, into: &result)
                if byte == 0x22 {
                    index += 1
                    return result
                }

                index += 1
                guard let escaped = currentByte else { throw .malformed }
                index += 1
                switch escaped {
                case 0x22:
                    try appendScalar("\"", into: &result)
                case 0x5C:
                    try appendScalar("\\", into: &result)
                case 0x2F:
                    try appendScalar("/", into: &result)
                case 0x62:
                    try appendScalar("\u{0008}", into: &result)
                case 0x66:
                    try appendScalar("\u{000C}", into: &result)
                case 0x6E:
                    try appendScalar("\n", into: &result)
                case 0x72:
                    try appendScalar("\r", into: &result)
                case 0x74:
                    try appendScalar("\t", into: &result)
                case 0x75:
                    try appendUnicodeEscape(into: &result)
                default:
                    throw .malformed
                }
                segmentStart = index
            } else {
                guard byte >= 0x20 else { throw .malformed }
                index += 1
            }
        }
        throw .malformed
    }

    private mutating func appendUnicodeEscape(
        into result: inout String
    ) throws(StrictJSONError) {
        let first = try parseHexQuad()
        let scalarValue: UInt32
        if (0xD800...0xDBFF).contains(first) {
            guard consumeIfPresent(0x5C), consumeIfPresent(0x75) else { throw .malformed }
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else { throw .malformed }
            scalarValue = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
        } else {
            guard !(0xDC00...0xDFFF).contains(first) else { throw .malformed }
            scalarValue = first
        }
        guard let scalar = UnicodeScalar(scalarValue) else { throw .malformed }
        try budgetTracker.consumeDecodedStringBytes(scalar.utf8.count)
        result.unicodeScalars.append(scalar)
    }

    private mutating func parseHexQuad() throws(StrictJSONError) -> UInt32 {
        guard index + 4 <= bytes.count else { throw .malformed }
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let digit = hexValue(bytes[index]) else { throw .malformed }
            value = (value << 4) | UInt32(digit)
            index += 1
        }
        return value
    }

    private mutating func parseNumber() throws(StrictJSONError) -> String {
        let start = index
        _ = consumeIfPresent(0x2D)
        guard let firstDigit = currentByte else { throw .malformed }
        if firstDigit == 0x30 {
            index += 1
            if let next = currentByte, (0x30...0x39).contains(next) { throw .malformed }
        } else {
            guard (0x31...0x39).contains(firstDigit) else { throw .malformed }
            index += 1
            while let byte = currentByte, (0x30...0x39).contains(byte) { index += 1 }
        }

        if consumeIfPresent(0x2E) {
            guard consumeDigits() else { throw .malformed }
        }
        if let byte = currentByte, byte == 0x65 || byte == 0x45 {
            index += 1
            if let sign = currentByte, sign == 0x2B || sign == 0x2D { index += 1 }
            guard consumeDigits() else { throw .malformed }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func consumeDigits() -> Bool {
        let start = index
        while let byte = currentByte, (0x30...0x39).contains(byte) { index += 1 }
        return index > start
    }

    private mutating func appendUTF8Segment(
        from start: Int,
        to end: Int,
        into result: inout String
    ) throws(StrictJSONError) {
        try budgetTracker.consumeDecodedStringBytes(end - start)
        guard let segment = String(bytes: bytes[start..<end], encoding: .utf8) else {
            throw .malformed
        }
        result.append(segment)
    }

    private mutating func appendScalar(
        _ scalar: UnicodeScalar,
        into result: inout String
    ) throws(StrictJSONError) {
        try budgetTracker.consumeDecodedStringBytes(scalar.utf8.count)
        result.unicodeScalars.append(scalar)
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws(StrictJSONError) {
        let expected = Array(String(describing: literal).utf8)
        guard index + expected.count <= bytes.count,
            Array(bytes[index..<(index + expected.count)]) == expected
        else {
            throw .malformed
        }
        index += expected.count
    }

    private mutating func consume(_ expected: UInt8) throws(StrictJSONError) {
        guard consumeIfPresent(expected) else { throw .malformed }
    }

    private mutating func consumeIfPresent(_ expected: UInt8) -> Bool {
        guard currentByte == expected else { return false }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            index += 1
        }
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }
}
