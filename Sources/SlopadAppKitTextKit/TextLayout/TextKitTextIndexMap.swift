import Foundation
import SlopadCoreModel

// MARK: - TextKitTextIndexMap

/// A request-local map between Slopad grapheme boundaries and TextKit UTF-16 boundaries.
///
/// The map is built in one pass when a layout request is prepared. Lookups then avoid
/// repeatedly scanning a String prefix for every caret, hit-test, and navigation operation.
struct TextKitTextIndexMap: Sendable {
    private static let invalidGraphemeOffset = -1

    private let utf16OffsetsByGraphemeBoundary: [Int]
    private let graphemeOffsetsByUTF16Boundary: [Int]

    init(text: String) {
        var utf16Offsets = [0]
        var textIndex = text.startIndex
        var utf16Offset = 0

        while textIndex != text.endIndex {
            let nextIndex = text.index(after: textIndex)
            utf16Offset += text[textIndex..<nextIndex].utf16.count
            utf16Offsets.append(utf16Offset)
            textIndex = nextIndex
        }

        var graphemeOffsets = [Int](
            repeating: Self.invalidGraphemeOffset,
            count: utf16Offset + 1
        )
        for (graphemeOffset, boundaryUTF16Offset) in utf16Offsets.enumerated() {
            graphemeOffsets[boundaryUTF16Offset] = graphemeOffset
        }

        utf16OffsetsByGraphemeBoundary = utf16Offsets
        graphemeOffsetsByUTF16Boundary = graphemeOffsets
    }

    var graphemeCount: Int {
        utf16OffsetsByGraphemeBoundary.count - 1
    }

    var utf16Count: Int {
        graphemeOffsetsByUTF16Boundary.count - 1
    }

    func utf16Offset(forGraphemeOffset offset: Int) -> Int? {
        guard (0...graphemeCount).contains(offset) else { return nil }
        return utf16OffsetsByGraphemeBoundary[offset]
    }

    func nsRange(clamping range: SlopadCoreModel.TextRange) -> NSRange {
        let clamped = range.clamped(to: graphemeCount)
        let lower = utf16OffsetsByGraphemeBoundary[clamped.lowerBound]
        let upper = utf16OffsetsByGraphemeBoundary[clamped.upperBound]
        return NSRange(location: lower, length: upper - lower)
    }

    func textRange(for range: NSRange) -> SlopadCoreModel.TextRange? {
        guard
            range.location != NSNotFound,
            range.location >= 0,
            range.length >= 0,
            range.location <= utf16Count,
            range.length <= utf16Count - range.location
        else { return nil }

        let upperBound = range.location + range.length
        let lowerOffset = graphemeOffsetsByUTF16Boundary[range.location]
        let upperOffset = graphemeOffsetsByUTF16Boundary[upperBound]
        guard
            lowerOffset != Self.invalidGraphemeOffset,
            upperOffset != Self.invalidGraphemeOffset
        else { return nil }
        return SlopadCoreModel.TextRange(lowerOffset, upperOffset)
    }

    func clampedUTF16Range(_ range: NSRange) -> NSRange? {
        guard
            range.location != NSNotFound,
            range.location >= 0,
            range.length >= 0,
            range.location <= Int.max - range.length
        else { return nil }

        let rawUpperBound = range.location + range.length
        let lowerBound = min(range.location, utf16Count)
        let upperBound = min(max(lowerBound, rawUpperBound), utf16Count)
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    func extendsPastUTF16Bounds(_ range: NSRange) -> Bool {
        guard
            range.location != NSNotFound,
            range.location >= 0,
            range.length >= 0,
            range.location <= Int.max - range.length
        else { return false }
        return range.location > utf16Count || range.location + range.length > utf16Count
    }
}
