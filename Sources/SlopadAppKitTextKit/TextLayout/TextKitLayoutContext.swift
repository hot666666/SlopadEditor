import AppKit
import Foundation
import SlopadCoreModel

// MARK: - TextKitLayoutContext

final class TextKitLayoutContext: @unchecked Sendable {
    private let lock = NSLock()
    private let textStorage = NSTextStorage()
    private let textContentStorage = NSTextContentStorage()
    private let textLayoutManager = NSTextLayoutManager()
    private let textContainer = NSTextContainer(
        size: CGSize(width: 1, height: CGFloat.greatestFiniteMagnitude)
    )
    private var preparedLayoutState: PreparedLayoutState?

    private static let trailingLineBreakSentinel = "\u{200B}"

    private struct PreparedLayoutKey: Equatable {
        let request: BlockMeasureRequest
        let style: TextKitEditorStyle
    }

    private final class PreparedLayoutState {
        let key: PreparedLayoutKey
        let canonicalText: String
        let layoutText: String
        let layoutUTF16Count: Int

        // Measurement and drawing do not need index conversion. Build these arrays only
        // when geometry/navigation first crosses the grapheme↔UTF-16 boundary.
        lazy var canonicalIndexMap = TextKitTextIndexMap(text: canonicalText)
        lazy var layoutIndexMap = layoutText == canonicalText
            ? canonicalIndexMap
            : TextKitTextIndexMap(text: layoutText)

        init(
            key: PreparedLayoutKey,
            canonicalText: String,
            layoutText: String,
            layoutUTF16Count: Int
        ) {
            self.key = key
            self.canonicalText = canonicalText
            self.layoutText = layoutText
            self.layoutUTF16Count = layoutUTF16Count
        }
    }

    init() {
        textContainer.lineFragmentPadding = 0
        textContentStorage.textStorage = textStorage
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textLayoutManager.textContainer = textContainer
        textLayoutManager.textSelectionNavigation.allowsNonContiguousRanges = false
    }

    func measure(
        _ request: BlockMeasureRequest,
        style: TextKitEditorStyle,
        minimumHeight: CGFloat
    ) -> CGFloat {
        lock.lock()
        defer { lock.unlock() }

        _ = prepareLayout(for: request, style: style)

        var measuredHeight: CGFloat = 0
        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            measuredHeight = max(measuredHeight, fragment.layoutFragmentFrame.maxY)
            return true
        }

        return max(minimumHeight, measuredHeight)
    }

    func draw(
        _ request: BlockMeasureRequest,
        in frame: CGRect,
        style: TextKitEditorStyle,
        context: CGContext
    ) {
        lock.lock()
        defer { lock.unlock() }

        _ = prepareLayout(for: request, style: style)

        context.saveGState()
        context.translateBy(x: frame.minX, y: frame.minY)
        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
            return true
        }
        context.restoreGState()
    }

    func lineFragments(
        for request: BlockMeasureRequest,
        style: TextKitEditorStyle
    ) -> [LineFragmentSnapshot] {
        lock.lock()
        defer { lock.unlock() }

        let prepared = prepareLayout(for: request, style: style)
        let canonicalIndexMap = prepared.canonicalIndexMap
        let layoutIndexMap = prepared.layoutIndexMap
        let textOrigin = style.textOrigin(depth: request.depth, kind: request.kind)
        var fragments: [LineFragmentSnapshot] = []

        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            for line in fragment.textLineFragments {
                let rect = line.typographicBounds.offsetBy(
                    dx: fragment.layoutFragmentFrame.origin.x + textOrigin.x,
                    dy: fragment.layoutFragmentFrame.origin.y + textOrigin.y
                )
                let textRange = layoutIndexMap.textRange(for: line.characterRange)?
                    .clamped(to: canonicalIndexMap.graphemeCount)
                    ?? SlopadCoreModel.TextRange.point(0)
                fragments.append(
                    LineFragmentSnapshot(
                        blockID: request.blockID,
                        range: textRange,
                        rect: EditorRect(
                            x: Double(rect.origin.x),
                            y: Double(rect.origin.y),
                            width: Double(rect.size.width),
                            height: Double(rect.size.height)
                        )
                    )
                )
            }
            return true
        }

        return fragments
    }

    func caretRect(
        position: TextPosition,
        navigationContext: TextNavigationContext?,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle
    ) -> CGRect? {
        lock.lock()
        defer { lock.unlock() }

        let prepared = prepareLayout(for: request, style: style)
        let indexMap = prepared.canonicalIndexMap
        guard var rect = caretRectWithoutLock(
            position: position,
            request: request,
            style: style,
            indexMap: indexMap
        ) else { return nil }
        if let caretInlineOffset = navigationContext?.caretInlineOffset,
            caretInlineOffset.isFinite
        {
            let textOrigin = style.textOrigin(depth: request.depth, kind: request.kind)
            rect.origin.x = textOrigin.x + CGFloat(caretInlineOffset)
        }
        return rect
    }

    func selectionRects(
        for range: SlopadCoreModel.TextRange,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle
    ) -> [CGRect] {
        lock.lock()
        defer { lock.unlock() }

        let prepared = prepareLayout(for: request, style: style)
        let indexMap = prepared.canonicalIndexMap
        let clamped = range.clamped(to: indexMap.graphemeCount)
        guard
            let textRange = nsTextRange(
                for: clamped,
                indexMap: indexMap
            )
        else { return [] }

        let textOrigin = style.textOrigin(depth: request.depth, kind: request.kind)
        var rects: [CGRect] = []
        textLayoutManager.enumerateTextSegments(
            in: textRange,
            type: .selection,
            options: []
        ) { _, rect, _, _ in
            rects.append(rect.offsetBy(dx: textOrigin.x, dy: textOrigin.y))
            return true
        }
        return rects
    }

    func textHitTest(
        to point: CGPoint,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle
    ) -> TextHitTestResult? {
        lock.lock()
        defer { lock.unlock() }

        let prepared = prepareLayout(for: request, style: style)
        let indexMap = prepared.canonicalIndexMap
        let textOrigin = style.textOrigin(depth: request.depth, kind: request.kind)
        let containerPoint = CGPoint(x: point.x - textOrigin.x, y: point.y - textOrigin.y)
        guard
            let nativeSelection = nativeTextSelection(at: containerPoint),
            let nativeRange = nativeSelection.textRanges.only,
            let rawRange = nativeNSRange(for: nativeRange),
            let boundedRange = indexMap.clampedUTF16Range(rawRange),
            let selection = slopadSelection(
                from: nativeSelection,
                boundedRange: boundedRange,
                blockID: request.blockID,
                indexMap: indexMap
            )
        else { return nil }
        return TextHitTestResult(
            position: selection.focus,
            navigationContext: navigationContext(
                from: nativeSelection,
                resolvedSelection: selection,
                request: request,
                style: style,
                indexMap: indexMap
            )
        )
    }

    func navigate(
        selection: TextSelection,
        context: TextNavigationContext?,
        direction: TextNavigationDirection,
        destination: TextNavigationDestination,
        extending: Bool,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle
    ) -> TextNavigationResolution {
        lock.lock()
        defer { lock.unlock() }

        let prepared = prepareLayout(for: request, style: style)
        let indexMap = prepared.canonicalIndexMap
        guard
            let nativeSelection = nativeSelection(
                for: selection,
                context: context,
                in: request,
                indexMap: indexMap
            )
        else {
            return .unchanged
        }

        let outcome = nativeNavigationResult(
            from: nativeSelection,
            direction: direction,
            destination: destination,
            extending: extending,
            canonicalIndexMap: indexMap,
            layoutUTF16Count: prepared.layoutUTF16Count
        )
        let result: NativeNavigationResult
        switch outcome {
        case .result(let nativeResult):
            result = nativeResult
        case .failure(let failure):
            return textKitNavigationResolution(
                for: failure,
                selection: selection,
                direction: direction,
                request: request,
                graphemeCount: indexMap.graphemeCount
            )
        }
        guard
            let converted = slopadSelection(
                from: result.selection,
                boundedRange: result.boundedRange,
                blockID: request.blockID,
                indexMap: indexMap
            )
        else { return .unchanged }

        if request.text.isEmpty {
            return textKitNavigationResolution(
                for: .destinationMissing,
                selection: selection,
                direction: direction,
                request: request,
                graphemeCount: indexMap.graphemeCount
            )
        }

        let nextContext = navigationContext(
            from: result.selection,
            resolvedSelection: converted,
            direction: direction,
            extending: extending,
            request: request,
            style: style,
            indexMap: indexMap
        )

        if !selection.hasSameLogicalEndpoints(as: converted) {
            return .selection(
                converted,
                context: nextContext
            )
        }
        if indexMap.extendsPastUTF16Bounds(result.rawRange) {
            return .boundary(.end)
        }
        let alternateCaretChanged =
            context?.caretInlineOffset != nextContext?.caretInlineOffset
            && (context?.caretInlineOffset != nil || nextContext?.caretInlineOffset != nil)
        if nativeSelection.affinity != result.selection.affinity || alternateCaretChanged {
            return .selection(
                converted,
                context: nextContext
            )
        }
        return textKitNavigationResolution(
            for: .destinationMissing,
            selection: selection,
            direction: direction,
            request: request,
            graphemeCount: indexMap.graphemeCount
        )
    }

    func wordRange(
        containing position: TextPosition,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle
    ) -> SlopadCoreModel.TextRange? {
        guard position.blockID == request.blockID else { return nil }
        guard !request.text.isEmpty else { return .point(0) }

        lock.lock()
        defer { lock.unlock() }

        let prepared = prepareLayout(for: request, style: style)
        let indexMap = prepared.canonicalIndexMap
        guard
            let nativeSelection = nativeSelection(
                for: position,
                in: request,
                indexMap: indexMap
            )
        else { return nil }
        let enclosingSelection = textLayoutManager.textSelectionNavigation.textSelection(
            for: .word,
            enclosing: nativeSelection
        )
        guard
            let nativeRange = enclosingSelection.textRanges.only,
            let rawRange = nativeNSRange(for: nativeRange),
            let boundedRange = indexMap.clampedUTF16Range(rawRange),
            let range = indexMap.textRange(for: boundedRange)
        else {
            return .point(min(max(0, position.offset), indexMap.graphemeCount))
        }
        return range
    }

    func deletionRange(
        for selection: TextSelection,
        direction: TextNavigationDirection,
        destination: TextNavigationDestination,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle
    ) -> SlopadCoreModel.TextRange? {
        lock.lock()
        defer { lock.unlock() }

        let prepared = prepareLayout(for: request, style: style)
        let indexMap = prepared.canonicalIndexMap
        guard
            let nativeSelection = nativeSelection(
                for: selection,
                in: request,
                indexMap: indexMap
            )
        else {
            return nil
        }
        let deletionRanges = textLayoutManager.textSelectionNavigation.deletionRanges(
            for: nativeSelection,
            direction: direction.native,
            destination: destination.native,
            allowsDecomposition: false
        )
        guard
            let nativeRange = deletionRanges.only,
            let rawRange = nativeNSRange(for: nativeRange),
            let boundedRange = indexMap.clampedUTF16Range(rawRange),
            boundedRange.length > 0,
            let range = indexMap.textRange(for: boundedRange),
            !range.isEmpty
        else { return nil }
        return range
    }

    @discardableResult
    private func prepareLayout(
        for request: BlockMeasureRequest,
        style: TextKitEditorStyle
    ) -> PreparedLayoutState {
        let key = PreparedLayoutKey(request: request, style: style)
        if let preparedLayoutState, preparedLayoutState.key == key {
            return preparedLayoutState
        }

        let attributed = TextKitAttributedStringBuilder.attributedString(for: request, style: style)
        let layoutText = Self.normalizedTrailingLineBreak(in: attributed)

        let textWidth = style.textWidth(
            availableWidth: request.availableWidth,
            depth: request.depth
        )
        let textContainerSizeChanged = textContainer.size.width != textWidth
        if textContainerSizeChanged {
            textContainer.size = CGSize(
                width: textWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        textStorage.setAttributedString(layoutText)
        textLayoutManager.textSelectionNavigation.flushLayoutCache()
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        if textContainerSizeChanged {
            // TextKit's navigation cache retains stale visual caret order across container
            // width changes even after flushLayoutCache(). Recreate only on width changes.
            textLayoutManager.textSelectionNavigation = NSTextSelectionNavigation(
                dataSource: textLayoutManager
            )
        }
        let prepared = PreparedLayoutState(
            key: key,
            canonicalText: request.text,
            layoutText: layoutText.string,
            layoutUTF16Count: layoutText.length
        )
        preparedLayoutState = prepared
        return prepared
    }

    private func caretRectWithoutLock(
        position: TextPosition,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle,
        indexMap: TextKitTextIndexMap
    ) -> CGRect? {
        let nsOffset = indexMap.nsRange(
            clamping: SlopadCoreModel.TextRange.point(position.offset)
        ).location
        guard
            let location = textContentStorage.location(
                textLayoutManager.documentRange.location,
                offsetBy: nsOffset
            )
        else { return nil }

        let textOrigin = style.textOrigin(depth: request.depth, kind: request.kind)
        let textRange = NSTextRange(location: location)
        var options: NSTextLayoutManager.SegmentOptions = [.rangeNotRequired]
        if position.affinity == .upstream {
            options.insert(.upstreamAffinity)
        }
        var caretRect: CGRect?
        textLayoutManager.enumerateTextSegments(
            in: textRange,
            type: .standard,
            options: options
        ) { _, rect, _, _ in
            caretRect = rect.offsetBy(dx: textOrigin.x, dy: textOrigin.y)
            return false
        }
        if var caretRect {
            caretRect.size.width = max(1, caretRect.width)
            return caretRect
        }
        return nil
    }

    private func nsTextRange(
        for range: SlopadCoreModel.TextRange,
        indexMap: TextKitTextIndexMap
    ) -> NSTextRange? {
        let nsRange = indexMap.nsRange(clamping: range)
        guard
            let start = textContentStorage.location(
                textLayoutManager.documentRange.location,
                offsetBy: nsRange.location
            ),
            let end = textContentStorage.location(start, offsetBy: nsRange.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    private func nativeSelection(
        for selection: TextSelection,
        context: TextNavigationContext? = nil,
        in request: BlockMeasureRequest,
        indexMap: TextKitTextIndexMap
    ) -> NSTextSelection? {
        guard
            selection.isSingleBlock,
            selection.anchor.blockID == request.blockID,
            selection.focus.blockID == request.blockID,
            (0...indexMap.graphemeCount).contains(selection.anchor.offset),
            (0...indexMap.graphemeCount).contains(selection.focus.offset),
            let range = selection.rangeInSingleBlock
        else { return nil }

        let result: NSTextSelection
        if range.isEmpty {
            guard
                let collapsed = nativeSelection(
                    for: selection.focus,
                    in: request,
                    indexMap: indexMap
                )
            else {
                return nil
            }
            result = collapsed
        } else {
            guard let nativeRange = nsTextRange(for: range, indexMap: indexMap) else { return nil }
            let affinity: NSTextSelection.Affinity =
                selection.focus.offset < selection.anchor.offset ? .upstream : .downstream
            result = NSTextSelection(
                range: nativeRange,
                affinity: affinity,
                granularity: .character
            )
        }
        if let context, context.preferredInlineOffset.isFinite {
            result.anchorPositionOffset = CGFloat(context.preferredInlineOffset)
        }
        return result
    }

    private func nativeSelection(
        for position: TextPosition,
        in request: BlockMeasureRequest,
        indexMap: TextKitTextIndexMap
    ) -> NSTextSelection? {
        guard
            position.blockID == request.blockID,
            (0...indexMap.graphemeCount).contains(position.offset),
            let utf16Offset = indexMap.utf16Offset(forGraphemeOffset: position.offset)
        else { return nil }
        guard
            let location = textContentStorage.location(
                textLayoutManager.documentRange.location,
                offsetBy: utf16Offset
            )
        else { return nil }
        return NSTextSelection(location, affinity: position.affinity.native)
    }

    private func nativeTextSelection(
        at containerPoint: CGPoint
    ) -> NSTextSelection? {
        let usageBounds = textLayoutManager.usageBoundsForTextContainer
        let minimumX = min(0, containerPoint.x)
        let minimumY = min(0, containerPoint.y)
        let maximumX = max(textContainer.size.width, containerPoint.x, 1)
        let maximumY = max(usageBounds.maxY, containerPoint.y, 1)
        let interactionBounds = CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        ).insetBy(dx: -1, dy: -1)
        return textLayoutManager.textSelectionNavigation.textSelections(
            interactingAt: containerPoint,
            inContainerAt: textLayoutManager.documentRange.location,
            anchors: [],
            modifiers: [],
            selecting: false,
            bounds: interactionBounds
        ).only
    }

    private struct NativeNavigationResult {
        let selection: NSTextSelection
        let rawRange: NSRange
        let boundedRange: NSRange
    }

    private enum NativeNavigationOutcome {
        case result(NativeNavigationResult)
        case failure(TextKitNativeNavigationFailure)
    }

    private func nativeNavigationResult(
        from selection: NSTextSelection,
        direction: TextNavigationDirection,
        destination: TextNavigationDestination,
        extending: Bool,
        canonicalIndexMap: TextKitTextIndexMap,
        layoutUTF16Count: Int
    ) -> NativeNavigationOutcome {
        var current = selection
        var receivedCandidate = false
        let attemptLimit = max(2, layoutUTF16Count + 1)

        for _ in 0..<attemptLimit {
            guard
                let candidate = textLayoutManager.textSelectionNavigation.destinationSelection(
                    for: current,
                    direction: direction.native,
                    destination: destination.native,
                    extending: extending,
                    confined: false
                )
            else {
                return .failure(receivedCandidate ? .invalidCandidate : .destinationMissing)
            }
            receivedCandidate = true
            guard
                let nativeRange = candidate.textRanges.only,
                let rawRange = nativeNSRange(for: nativeRange),
                let boundedRange = canonicalIndexMap.clampedUTF16Range(rawRange)
            else { return .failure(.invalidCandidate) }

            if canonicalIndexMap.textRange(for: boundedRange) != nil {
                return .result(
                    NativeNavigationResult(
                        selection: candidate,
                        rawRange: rawRange,
                        boundedRange: boundedRange
                    )
                )
            }

            guard destination == .character else {
                return .failure(.invalidCandidate)
            }
            if let currentRange = current.textRanges.only,
                let currentRawRange = nativeNSRange(for: currentRange),
                currentRawRange == rawRange,
                current.affinity == candidate.affinity
            {
                return .failure(.invalidCandidate)
            }
            current = candidate
        }
        return .failure(.invalidCandidate)
    }

    private func nativeNSRange(for range: NSTextRange) -> NSRange? {
        let documentStart = textLayoutManager.documentRange.location
        let start = textContentStorage.offset(from: documentStart, to: range.location)
        let end = textContentStorage.offset(from: documentStart, to: range.endLocation)
        guard
            start != NSNotFound,
            end != NSNotFound,
            start >= 0,
            end >= start
        else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private func slopadSelection(
        from nativeSelection: NSTextSelection,
        boundedRange: NSRange,
        blockID: BlockID,
        indexMap: TextKitTextIndexMap
    ) -> TextSelection? {
        guard let range = indexMap.textRange(for: boundedRange) else { return nil }
        if range.isEmpty {
            let position = TextPosition(
                blockID: blockID,
                offset: range.lowerBound,
                affinity: nativeSelection.affinity.slopad
            )
            return TextSelection(anchor: position, focus: position)
        }

        let lower = TextPosition(blockID: blockID, offset: range.lowerBound)
        let upper = TextPosition(blockID: blockID, offset: range.upperBound)
        return nativeSelection.affinity == .upstream
            ? TextSelection(anchor: upper, focus: lower)
            : TextSelection(anchor: lower, focus: upper)
    }

    private func navigationContext(
        from nativeSelection: NSTextSelection,
        resolvedSelection: TextSelection,
        direction: TextNavigationDirection,
        extending: Bool,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle,
        indexMap: TextKitTextIndexMap
    ) -> TextNavigationContext? {
        let preferredInlineOffset = Double(nativeSelection.anchorPositionOffset)
        guard preferredInlineOffset.isFinite else { return nil }
        guard
            direction.isPhysical,
            !extending
        else {
            return TextNavigationContext(preferredInlineOffset: preferredInlineOffset)
        }

        return TextNavigationContext(
            preferredInlineOffset: preferredInlineOffset,
            caretInlineOffset: validatedCaretInlineOffset(
                preferredInlineOffset,
                resolvedSelection: resolvedSelection,
                request: request,
                style: style,
                indexMap: indexMap
            )
        )
    }

    private func navigationContext(
        from nativeSelection: NSTextSelection,
        resolvedSelection: TextSelection,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle,
        indexMap: TextKitTextIndexMap
    ) -> TextNavigationContext? {
        let preferredInlineOffset = Double(nativeSelection.anchorPositionOffset)
        guard preferredInlineOffset.isFinite else { return nil }
        return TextNavigationContext(
            preferredInlineOffset: preferredInlineOffset,
            caretInlineOffset: validatedCaretInlineOffset(
                preferredInlineOffset,
                resolvedSelection: resolvedSelection,
                request: request,
                style: style,
                indexMap: indexMap
            )
        )
    }

    private func validatedCaretInlineOffset(
        _ preferredInlineOffset: Double,
        resolvedSelection: TextSelection,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle,
        indexMap: TextKitTextIndexMap
    ) -> Double? {
        guard
            resolvedSelection.rangeInSingleBlock?.isEmpty == true,
            let ordinaryCaretRect = caretRectWithoutLock(
                position: resolvedSelection.focus,
                request: request,
                style: style,
                indexMap: indexMap
            )
        else { return nil }

        let textOrigin = style.textOrigin(depth: request.depth, kind: request.kind)
        let ordinaryInlineOffset = ordinaryCaretRect.minX - textOrigin.x
        guard abs(CGFloat(preferredInlineOffset) - ordinaryInlineOffset) > 0.5 else {
            return nil
        }
        let probePoint = CGPoint(
            x: CGFloat(preferredInlineOffset),
            y: ordinaryCaretRect.midY - textOrigin.y
        )
        guard
            let hitSelection = nativeTextSelection(at: probePoint),
            let hitNativeRange = hitSelection.textRanges.only,
            let hitRawRange = nativeNSRange(for: hitNativeRange),
            let hitBoundedRange = indexMap.clampedUTF16Range(hitRawRange),
            let hitResult = slopadSelection(
                from: hitSelection,
                boundedRange: hitBoundedRange,
                blockID: request.blockID,
                indexMap: indexMap
            ),
            hitResult.focus == resolvedSelection.focus
        else { return nil }
        return preferredInlineOffset
    }

    private static func normalizedTrailingLineBreak(
        in text: NSAttributedString
    ) -> NSAttributedString {
        guard text.length > 0, text.string.hasSuffix("\n") else { return text }
        let markerAttributes = text.attributes(at: text.length - 1, effectiveRange: nil)
        let normalized = NSMutableAttributedString(attributedString: text)
        normalized.append(
            NSAttributedString(string: trailingLineBreakSentinel, attributes: markerAttributes)
        )
        return normalized
    }
}

enum TextKitNativeNavigationFailure: Equatable {
    case destinationMissing
    case invalidCandidate
}

func textKitNavigationResolution(
    for failure: TextKitNativeNavigationFailure,
    selection: TextSelection,
    direction: TextNavigationDirection,
    request: BlockMeasureRequest,
    graphemeCount: Int
) -> TextNavigationResolution {
    guard
        failure == .destinationMissing,
        selection.isSingleBlock,
        selection.anchor.blockID == request.blockID,
        selection.focus.blockID == request.blockID,
        (0...graphemeCount).contains(selection.anchor.offset),
        (0...graphemeCount).contains(selection.focus.offset)
    else { return .unchanged }

    let offset = selection.focus.offset
    if graphemeCount == 0 {
        switch direction {
        case .backward, .left:
            return .boundary(.start)
        case .forward, .right:
            return .boundary(.end)
        }
    }
    if offset == 0 { return .boundary(.start) }
    if offset == graphemeCount { return .boundary(.end) }
    return .unchanged
}

private extension TextNavigationDirection {
    var native: NSTextSelectionNavigation.Direction {
        switch self {
        case .backward: .backward
        case .forward: .forward
        case .left: .left
        case .right: .right
        }
    }

    var isPhysical: Bool {
        switch self {
        case .left, .right: true
        case .backward, .forward: false
        }
    }
}

private extension TextNavigationDestination {
    var native: NSTextSelectionNavigation.Destination {
        switch self {
        case .character: .character
        case .word: .word
        }
    }
}

private extension TextAffinity {
    var native: NSTextSelection.Affinity {
        switch self {
        case .upstream: .upstream
        case .downstream: .downstream
        }
    }
}

private extension NSTextSelection.Affinity {
    var slopad: TextAffinity {
        switch self {
        case .upstream: .upstream
        case .downstream: .downstream
        @unknown default: .downstream
        }
    }
}

private extension TextSelection {
    func hasSameLogicalEndpoints(as other: TextSelection) -> Bool {
        anchor.blockID == other.anchor.blockID
            && anchor.offset == other.anchor.offset
            && focus.blockID == other.focus.blockID
            && focus.offset == other.focus.offset
    }
}

private extension Collection {
    var only: Element? {
        guard count == 1 else { return nil }
        return first
    }
}
