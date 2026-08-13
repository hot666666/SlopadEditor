// MARK: - String Text Range

extension String {
    package func indexAtGraphemeOffset(_ offset: Int) -> String.Index {
        precondition(offset >= 0 && offset <= count, "Grapheme offset out of bounds")
        return index(startIndex, offsetBy: offset)
    }

    package func substring(in range: TextRange) -> String {
        let clamped = range.clamped(to: count)
        let lower = indexAtGraphemeOffset(clamped.lowerBound)
        let upper = indexAtGraphemeOffset(clamped.upperBound)
        return String(self[lower..<upper])
    }
}
