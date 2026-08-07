// MARK: - Text Layout Capabilities

// One backend implements all four. They are declared separately so a consumer is handed
// only what it uses: `BlockLayout` needs a height and nothing else, and giving it caret
// geometry or word boundaries invites a layer that owns derived geometry to start answering
// questions about text meaning.
//
// Splitting the contracts is not splitting the implementation. Measurement, geometry, and
// drawing must agree on line breaks, so they have to come from one coherent backend — see
// ADR 0003.

/// Height and baseline for a block at a given width.
public protocol BlockMeasuring: Sendable {
    func measure(_ request: BlockMeasureRequest) -> BlockMeasurement
}

/// Where text sits once laid out: frames, line fragments, caret and selection rectangles,
/// and the reverse mapping from a point back to a position.
public protocol TextGeometryResolving: Sendable {
    func textFrame(for request: BlockMeasureRequest, measuredHeight: Double?) -> EditorRect
    func lineFragments(for request: BlockMeasureRequest) -> [LineFragmentSnapshot]
    func caretRect(for position: TextPosition, in request: BlockMeasureRequest) -> EditorRect?
    func caretRect(
        for position: TextPosition,
        navigationContext: TextNavigationContext?,
        in request: BlockMeasureRequest
    ) -> EditorRect?
    func selectionRects(for range: TextRange, in request: BlockMeasureRequest) -> [EditorRect]
    func textPosition(at point: EditorPoint, in request: BlockMeasureRequest) -> TextPosition
    func textHitTest(at point: EditorPoint, in request: BlockMeasureRequest) -> TextHitTestResult?
}

/// Movement through shaped text — physical direction and linguistic word boundaries, which
/// depend on the platform's own segmentation rather than on document order.
public protocol TextNavigationResolving: Sendable {
    func navigate(
        selection: TextSelection,
        context: TextNavigationContext?,
        direction: TextNavigationDirection,
        destination: TextNavigationDestination,
        extending: Bool,
        in request: BlockMeasureRequest
    ) -> TextNavigationResolution
    func wordRange(
        containing position: TextPosition,
        in request: BlockMeasureRequest
    ) -> TextRange?
}

/// The range a deletion should remove, which follows the same segmentation as navigation.
public protocol TextDeletionResolving: Sendable {
    func deletionRange(
        for selection: TextSelection,
        direction: TextNavigationDirection,
        destination: TextNavigationDestination,
        in request: BlockMeasureRequest
    ) -> TextRange?
}

// MARK: - BlockTextLayoutProtocol

/// The whole seam, for a backend to adopt and for `EditorSession` to hold.
///
/// Consumers should depend on the narrowest capability they need instead of this.
public protocol BlockTextLayoutProtocol:
    BlockMeasuring, TextGeometryResolving, TextNavigationResolving, TextDeletionResolving
{}

// MARK: - Portable Logical Fallback


// The documented logical fallback lives on the protocol that declares each method, not on
// the composed one. A backend adopting a single capability — a navigation-only test double,
// or a future non-text block type — has to receive these too, otherwise the split hands out
// contracts that cannot be satisfied without reimplementing text segmentation.

public extension TextGeometryResolving {
    func caretRect(
        for position: TextPosition,
        navigationContext: TextNavigationContext?,
        in request: BlockMeasureRequest
    ) -> EditorRect? {
        caretRect(for: position, in: request)
    }


    func textHitTest(
        at point: EditorPoint,
        in request: BlockMeasureRequest
    ) -> TextHitTestResult? {
        TextHitTestResult(position: textPosition(at: point, in: request))
    }

    /// Supplies logical LTR behavior for simple backends that do not own visual navigation.
    /// Platform text backends should override this for bidi and locale-aware segmentation.
}

public extension TextNavigationResolving {
    func navigate(
        selection: TextSelection,
        context: TextNavigationContext?,
        direction: TextNavigationDirection,
        destination: TextNavigationDestination,
        extending: Bool,
        in request: BlockMeasureRequest
    ) -> TextNavigationResolution {
        guard
            selection.isSingleBlock,
            selection.anchor.blockID == request.blockID,
            selection.focus.blockID == request.blockID,
            (0...request.text.count).contains(selection.anchor.offset),
            (0...request.text.count).contains(selection.focus.offset)
        else { return .unchanged }

        if !extending, let range = selection.rangeInSingleBlock, !range.isEmpty {
            let offset = direction.fallbackMovesTowardStart ? range.lowerBound : range.upperBound
            let position = TextPosition(blockID: request.blockID, offset: offset)
            return .selection(TextSelection(anchor: position, focus: position), context: nil)
        }

        let current = selection.focus.offset
        let target: Int
        switch destination {
        case .character:
            target = current + (direction.fallbackMovesTowardStart ? -1 : 1)
        case .word:
            target = direction.fallbackMovesTowardStart
                ? fallbackPreviousWordBoundary(in: request.text, from: current)
                : fallbackNextWordBoundary(in: request.text, from: current)
        }

        guard (0...request.text.count).contains(target), target != current else {
            return .boundary(direction.fallbackMovesTowardStart ? .start : .end)
        }
        let focus = TextPosition(blockID: request.blockID, offset: target)
        return .selection(
            extending
                ? TextSelection(anchor: selection.anchor, focus: focus)
                : TextSelection(anchor: focus, focus: focus),
            context: nil
        )
    }


    func wordRange(
        containing position: TextPosition,
        in request: BlockMeasureRequest
    ) -> TextRange? {
        guard position.blockID == request.blockID else { return nil }
        return fallbackWordRange(in: request.text, containing: position.offset)
    }

}

public extension TextDeletionResolving {
    func deletionRange(
        for selection: TextSelection,
        direction: TextNavigationDirection,
        destination: TextNavigationDestination,
        in request: BlockMeasureRequest
    ) -> TextRange? {
        guard
            selection.isSingleBlock,
            selection.focus.blockID == request.blockID,
            let selectedRange = selection.rangeInSingleBlock
        else { return nil }
        if !selectedRange.isEmpty {
            return selectedRange.clamped(to: request.text.count)
        }

        let offset = min(max(0, selection.focus.offset), request.text.count)
        let otherOffset: Int
        switch destination {
        case .character:
            otherOffset = offset + (direction.fallbackMovesTowardStart ? -1 : 1)
        case .word:
            otherOffset = direction.fallbackMovesTowardStart
                ? fallbackPreviousWordBoundary(in: request.text, from: offset)
                : fallbackNextWordBoundary(in: request.text, from: offset)
        }
        let clampedOtherOffset = min(max(0, otherOffset), request.text.count)
        let range = TextRange(
            min(offset, clampedOtherOffset),
            max(offset, clampedOtherOffset)
        )
        return range.isEmpty ? nil : range
    }
}

private extension TextNavigationDirection {
    var fallbackMovesTowardStart: Bool {
        switch self {
        case .backward, .left:
            return true
        case .forward, .right:
            return false
        }
    }
}

private func fallbackWordRange(in text: String, containing offset: Int) -> TextRange {
    guard !text.isEmpty else { return .point(0) }
    let characters = Array(text)
    var index = min(max(0, offset), characters.count)
    if index == characters.count {
        index -= 1
    }
    if characters[index].isWhitespace {
        if index > 0, !characters[index - 1].isWhitespace {
            index -= 1
        } else {
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
            guard index < characters.count else {
                return .point(min(max(0, offset), characters.count))
            }
        }
    }

    var lowerBound = index
    while lowerBound > 0, !characters[lowerBound - 1].isWhitespace {
        lowerBound -= 1
    }
    var upperBound = index
    while upperBound < characters.count, !characters[upperBound].isWhitespace {
        upperBound += 1
    }
    return TextRange(lowerBound, upperBound)
}

private func fallbackPreviousWordBoundary(in text: String, from offset: Int) -> Int {
    let characters = Array(text)
    var index = min(max(0, offset), characters.count)
    while index > 0, characters[index - 1].isWhitespace {
        index -= 1
    }
    while index > 0, !characters[index - 1].isWhitespace {
        index -= 1
    }
    return index
}

private func fallbackNextWordBoundary(in text: String, from offset: Int) -> Int {
    let characters = Array(text)
    var index = min(max(0, offset), characters.count)
    while index < characters.count, characters[index].isWhitespace {
        index += 1
    }
    while index < characters.count, !characters[index].isWhitespace {
        index += 1
    }
    return index
}
