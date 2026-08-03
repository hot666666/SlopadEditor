import Foundation
import SlopadCoreModel

// MARK: - TextRange NSRange

extension SlopadCoreModel.TextRange {
    public func textKitNSRange(in text: String) -> NSRange {
        let clamped = clamped(to: text.count)
        let lower = text.textKitIndexAtGraphemeOffset(clamped.lowerBound)
        let upper = text.textKitIndexAtGraphemeOffset(clamped.upperBound)
        let location: Int =
            lower.samePosition(in: text.utf16).map {
                text.utf16.distance(from: text.utf16.startIndex, to: $0)
            } ?? 0
        let end: Int =
            upper.samePosition(in: text.utf16).map {
                text.utf16.distance(from: text.utf16.startIndex, to: $0)
            } ?? location
        return NSRange(location: location, length: end - location)
    }
}

// MARK: - NSRange TextRange

extension NSRange {
    public func slopadTextRange(in text: String) -> SlopadCoreModel.TextRange? {
        let utf16Count = text.utf16.count
        guard
            location != NSNotFound,
            location >= 0,
            length >= 0,
            location <= utf16Count,
            length <= utf16Count - location,
            let lowerUTF16 = text.utf16.index(
                text.utf16.startIndex,
                offsetBy: location,
                limitedBy: text.utf16.endIndex
            ),
            let upperUTF16 = text.utf16.index(
                lowerUTF16,
                offsetBy: length,
                limitedBy: text.utf16.endIndex
            ),
            let lower = String.Index(lowerUTF16, within: text),
            let upper = String.Index(upperUTF16, within: text),
            (lower == text.endIndex || text.indices.contains(lower)),
            (upper == text.endIndex || text.indices.contains(upper))
        else {
            return nil
        }
        let lowerOffset = text.distance(from: text.startIndex, to: lower)
        let upperOffset = text.distance(from: text.startIndex, to: upper)
        return SlopadCoreModel.TextRange(lowerOffset, upperOffset)
    }
}

// MARK: - String Grapheme Offset

extension String {
    fileprivate func textKitIndexAtGraphemeOffset(_ offset: Int) -> String.Index {
        precondition(offset >= 0 && offset <= count, "Grapheme offset out of bounds")
        return index(startIndex, offsetBy: offset)
    }
}
