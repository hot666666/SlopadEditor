// MARK: - BlockContent EditingMutation

extension BlockContent {
    package mutating func insert(_ insertedText: String, at offset: Int) {
        let offset = TextRange.point(offset).clamped(to: text.count).lowerBound
        let index = text.indexAtGraphemeOffset(offset)
        text.insert(contentsOf: insertedText, at: index)
        let delta = insertedText.count
        marks = marks.compactMap { mark in
            var range = mark.range
            if range.lowerBound >= offset {
                range = range.shifted(by: delta)
            } else if range.upperBound > offset {
                range.upperBound += delta
            }
            return InlineMark(kind: mark.kind, range: range)
        }
        normalizeMarks()
        revision += 1
    }

    package mutating func delete(_ range: TextRange) {
        let clamped = range.clamped(to: text.count)
        guard !clamped.isEmpty else { return }
        let lower = text.indexAtGraphemeOffset(clamped.lowerBound)
        let upper = text.indexAtGraphemeOffset(clamped.upperBound)
        text.removeSubrange(lower..<upper)
        marks = marks.compactMap { mark in
            let lower = Self.mapOffsetAfterDeleting(mark.range.lowerBound, deleted: clamped)
            let upper = Self.mapOffsetAfterDeleting(mark.range.upperBound, deleted: clamped)
            guard upper > lower else { return nil }
            return InlineMark(kind: mark.kind, range: TextRange(lower, upper))
        }
        normalizeMarks()
        revision += 1
    }

    package mutating func addMark(kind: BlockContent.InlineMark.Kind, range: TextRange) {
        let clamped = range.clamped(to: text.count)
        guard !clamped.isEmpty else { return }
        marks.append(InlineMark(kind: kind, range: clamped))
        normalizeMarks()
        revision += 1
    }

    package mutating func clearMarks(in range: TextRange) {
        clearMarks(matching: nil, in: range)
    }

    /// Removes marks overlapping `range`, keeping the portions that fall outside it.
    ///
    /// `caseIdentity` selects which marks to remove and ignores associated values, so
    /// removing `.link` clears a link regardless of its destination. Passing `nil` removes
    /// every kind.
    package mutating func clearMarks(
        matching caseIdentity: BlockContent.InlineMark.Kind.CaseIdentity?,
        in range: TextRange
    ) {
        let clamped = range.clamped(to: text.count)
        guard !clamped.isEmpty else { return }
        marks = marks.flatMap { mark -> [InlineMark] in
            guard mark.range.intersects(clamped) else { return [mark] }
            if let caseIdentity, mark.kind.caseIdentity != caseIdentity { return [mark] }

            var remaining: [InlineMark] = []
            if mark.range.lowerBound < clamped.lowerBound {
                remaining.append(
                    InlineMark(
                        kind: mark.kind,
                        range: TextRange(mark.range.lowerBound, clamped.lowerBound)
                    ))
            }
            if clamped.upperBound < mark.range.upperBound {
                remaining.append(
                    InlineMark(
                        kind: mark.kind,
                        range: TextRange(clamped.upperBound, mark.range.upperBound)
                    ))
            }
            return remaining
        }
        normalizeMarks()
        revision += 1
    }

    /// Whether every character in `range` already carries a mark of this case.
    ///
    /// Toggling uses full coverage rather than any overlap so that applying a style to a
    /// partially styled selection completes it instead of clearing it.
    package func coversEntirely(
        _ caseIdentity: BlockContent.InlineMark.Kind.CaseIdentity,
        in range: TextRange
    ) -> Bool {
        let clamped = range.clamped(to: text.count)
        guard !clamped.isEmpty else { return false }
        let covering = marks
            .filter { $0.kind.caseIdentity == caseIdentity }
            .map(\.range)
            .sorted { $0.lowerBound < $1.lowerBound }

        var reached = clamped.lowerBound
        for range in covering {
            guard range.lowerBound <= reached else { break }
            reached = max(reached, range.upperBound)
            if reached >= clamped.upperBound { return true }
        }
        return reached >= clamped.upperBound
    }

    private mutating func normalizeMarks() {
        marks = BlockContent.normalizedMarks(marks, textLength: text.count)
    }

    private static func mapOffsetAfterDeleting(_ offset: Int, deleted: TextRange) -> Int {
        if offset <= deleted.lowerBound {
            return offset
        }
        if offset >= deleted.upperBound {
            return offset - deleted.length
        }
        return deleted.lowerBound
    }
}
