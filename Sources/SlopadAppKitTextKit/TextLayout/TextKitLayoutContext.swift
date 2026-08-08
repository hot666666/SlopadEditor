import AppKit
import Dispatch
import Foundation
import SlopadCoreModel

// MARK: - TextKitLayoutContext

/// `@unchecked Sendable` is safe because the one context-wide lock guards every access to
/// the mutable store and every retained AppKit/TextKit object graph, including pressure events.
final class TextKitLayoutContext: @unchecked Sendable {
    private let lock = NSLock()
    private var preparedLayouts: TextKitPreparedLayoutStore
    private var memoryPressureSource: (any DispatchSourceMemoryPressure)?

    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        private static let instrumentationLock = NSLock()
        private nonisolated(unsafe) static var aggregateInstrumentation =
            TextKitPreparedLayoutInstrumentationSnapshot.zero

        static var aggregateInstrumentationSnapshot:
            TextKitPreparedLayoutInstrumentationSnapshot
        {
            Self.instrumentationLock.lock()
            defer { Self.instrumentationLock.unlock() }
            return aggregateInstrumentation
        }
    #endif

    private static let trailingLineBreakSentinel = "\u{200B}"

    convenience init() {
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            self.init(policy: .benchmarkConfigured())
        #else
            self.init(policy: .productionDefault)
        #endif
    }

    init(policy: TextKitPreparedLayoutStorePolicy) {
        preparedLayouts = TextKitPreparedLayoutStore(policy: policy)

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.global(qos: .utility)
        )
        memoryPressureSource = source
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let pressure: TextKitPreparedLayoutMemoryPressure =
                source.data.contains(.critical) ? .critical : .warning
            self.handleMemoryPressure(pressure)
        }
        source.activate()
    }

    deinit {
        memoryPressureSource?.cancel()
        lock.lock()
        let before = preparedLayouts.snapshot
        preparedLayouts.removeAllForInvalidation()
        recordInstrumentationChange(from: before)
        lock.unlock()
    }

    func measure(
        _ request: BlockMeasureRequest,
        style: TextKitEditorStyle,
        minimumHeight: CGFloat
    ) -> CGFloat {
        lock.lock()
        defer { lock.unlock() }

        let prepared = prepareLayout(for: request, style: style)

        var measuredHeight: CGFloat = 0
        prepared.textLayoutManager.enumerateTextLayoutFragments(
            from: prepared.textLayoutManager.documentRange.location,
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

        let prepared = prepareLayout(for: request, style: style)

        context.saveGState()
        context.translateBy(x: frame.minX, y: frame.minY)
        prepared.textLayoutManager.enumerateTextLayoutFragments(
            from: prepared.textLayoutManager.documentRange.location,
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

        prepared.textLayoutManager.enumerateTextLayoutFragments(
            from: prepared.textLayoutManager.documentRange.location,
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
            indexMap: indexMap,
            prepared: prepared
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
                indexMap: indexMap,
                prepared: prepared
            )
        else { return [] }

        let textOrigin = style.textOrigin(depth: request.depth, kind: request.kind)
        var rects: [CGRect] = []
        prepared.textLayoutManager.enumerateTextSegments(
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
            let nativeSelection = nativeTextSelection(at: containerPoint, prepared: prepared),
            let nativeRange = nativeSelection.textRanges.only,
            let rawRange = nativeNSRange(for: nativeRange, prepared: prepared),
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
                indexMap: indexMap,
                prepared: prepared
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
                indexMap: indexMap,
                prepared: prepared
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
            layoutUTF16Count: prepared.layoutUTF16Count,
            prepared: prepared
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
            indexMap: indexMap,
            prepared: prepared
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
                indexMap: indexMap,
                prepared: prepared
            )
        else { return nil }
        let enclosingSelection = prepared.textLayoutManager.textSelectionNavigation.textSelection(
            for: .word,
            enclosing: nativeSelection
        )
        guard
            let nativeRange = enclosingSelection.textRanges.only,
            let rawRange = nativeNSRange(for: nativeRange, prepared: prepared),
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
                indexMap: indexMap,
                prepared: prepared
            )
        else {
            return nil
        }
        let deletionRanges = prepared.textLayoutManager.textSelectionNavigation.deletionRanges(
            for: nativeSelection,
            direction: direction.native,
            destination: destination.native,
            allowsDecomposition: false
        )
        guard
            let nativeRange = deletionRanges.only,
            let rawRange = nativeNSRange(for: nativeRange, prepared: prepared),
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
    ) -> TextKitPreparedLayoutState {
        let key = TextKitPreparedLayoutKey(request: request, style: style)
        let before = preparedLayouts.snapshot
        let prepared = preparedLayouts.preparedLayout(for: key) {
            let attributed = TextKitAttributedStringBuilder.attributedString(
                for: request,
                style: style
            )
            let layoutText = Self.normalizedTrailingLineBreak(in: attributed)
            let textWidth = style.textWidth(
                availableWidth: request.availableWidth,
                depth: request.depth
            )
            return TextKitPreparedLayoutState(
                key: key,
                attributedString: layoutText,
                textWidth: textWidth
            )
        }
        recordInstrumentationChange(from: before)
        return prepared
    }

    func setActiveBlockID(_ blockID: BlockID?) {
        lock.lock()
        defer { lock.unlock() }
        let before = preparedLayouts.snapshot
        preparedLayouts.setPinnedBlockID(blockID)
        recordInstrumentationChange(from: before)
    }

    func removeAllPreparedLayouts() {
        lock.lock()
        defer { lock.unlock() }
        let before = preparedLayouts.snapshot
        preparedLayouts.removeAllForInvalidation()
        recordInstrumentationChange(from: before)
    }

    func handleMemoryPressure(_ pressure: TextKitPreparedLayoutMemoryPressure) {
        lock.lock()
        defer { lock.unlock() }
        let before = preparedLayouts.snapshot
        preparedLayouts.handleMemoryPressure(pressure)
        recordInstrumentationChange(from: before)
    }

    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        func instrumentationSnapshot() -> TextKitPreparedLayoutInstrumentationSnapshot {
            lock.lock()
            defer { lock.unlock() }
            return TextKitPreparedLayoutInstrumentationSnapshot(preparedLayouts.snapshot)
        }

        private func recordInstrumentationChange(
            from before: TextKitPreparedLayoutStoreSnapshot
        ) {
            let after = preparedLayouts.snapshot
            Self.instrumentationLock.lock()
            defer { Self.instrumentationLock.unlock() }
            Self.aggregateInstrumentation.lookups += after.lookups - before.lookups
            Self.aggregateInstrumentation.hits += after.hits - before.hits
            Self.aggregateInstrumentation.prepares += after.prepares - before.prepares
            Self.aggregateInstrumentation.attributedStringBuilds +=
                after.attributedStringBuilds - before.attributedStringBuilds
            Self.aggregateInstrumentation.capacityEvictions +=
                after.capacityEvictions - before.capacityEvictions
            Self.aggregateInstrumentation.capacityRejections +=
                after.capacityRejections - before.capacityRejections
            Self.aggregateInstrumentation.pressureEvictions +=
                after.pressureEvictions - before.pressureEvictions
            Self.aggregateInstrumentation.invalidationRemovals +=
                after.invalidationRemovals - before.invalidationRemovals
            Self.aggregateInstrumentation.oversizedPinnedInsertions +=
                after.oversizedPinnedInsertions - before.oversizedPinnedInsertions
            Self.aggregateInstrumentation.residentEntryCount +=
                after.residentEntryCount - before.residentEntryCount
            Self.aggregateInstrumentation.residentEstimatedCost +=
                after.residentEstimatedCost - before.residentEstimatedCost
            Self.aggregateInstrumentation.pinnedEntryCount +=
                after.pinnedEntryCount - before.pinnedEntryCount
            Self.aggregateInstrumentation.overEstimatedCostLimitContextCount +=
                (after.isOverEstimatedCostLimit ? 1 : 0)
                - (before.isOverEstimatedCostLimit ? 1 : 0)
            if after.prepares > before.prepares {
                Self.aggregateInstrumentation.pinnedBlockIDAtLastPrepare =
                    after.pinnedBlockIDAtLastPrepare
            }
            Self.aggregateInstrumentation.residentEntryHighWater = max(
                Self.aggregateInstrumentation.residentEntryHighWater,
                Self.aggregateInstrumentation.residentEntryCount
            )
            Self.aggregateInstrumentation.residentEstimatedCostHighWater = max(
                Self.aggregateInstrumentation.residentEstimatedCostHighWater,
                Self.aggregateInstrumentation.residentEstimatedCost
            )
        }
    #else
        private func recordInstrumentationChange(
            from before: TextKitPreparedLayoutStoreSnapshot
        ) {
            _ = before
        }
    #endif

    private func caretRectWithoutLock(
        position: TextPosition,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle,
        indexMap: TextKitTextIndexMap,
        prepared: TextKitPreparedLayoutState
    ) -> CGRect? {
        let nsOffset = indexMap.nsRange(
            clamping: SlopadCoreModel.TextRange.point(position.offset)
        ).location
        guard
            let location = prepared.textContentStorage.location(
                prepared.textLayoutManager.documentRange.location,
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
        prepared.textLayoutManager.enumerateTextSegments(
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
        indexMap: TextKitTextIndexMap,
        prepared: TextKitPreparedLayoutState
    ) -> NSTextRange? {
        let nsRange = indexMap.nsRange(clamping: range)
        guard
            let start = prepared.textContentStorage.location(
                prepared.textLayoutManager.documentRange.location,
                offsetBy: nsRange.location
            ),
            let end = prepared.textContentStorage.location(start, offsetBy: nsRange.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    private func nativeSelection(
        for selection: TextSelection,
        context: TextNavigationContext? = nil,
        in request: BlockMeasureRequest,
        indexMap: TextKitTextIndexMap,
        prepared: TextKitPreparedLayoutState
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
                    indexMap: indexMap,
                    prepared: prepared
                )
            else {
                return nil
            }
            result = collapsed
        } else {
            guard
                let nativeRange = nsTextRange(
                    for: range,
                    indexMap: indexMap,
                    prepared: prepared
                )
            else { return nil }
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
        indexMap: TextKitTextIndexMap,
        prepared: TextKitPreparedLayoutState
    ) -> NSTextSelection? {
        guard
            position.blockID == request.blockID,
            (0...indexMap.graphemeCount).contains(position.offset),
            let utf16Offset = indexMap.utf16Offset(forGraphemeOffset: position.offset)
        else { return nil }
        guard
            let location = prepared.textContentStorage.location(
                prepared.textLayoutManager.documentRange.location,
                offsetBy: utf16Offset
            )
        else { return nil }
        return NSTextSelection(location, affinity: position.affinity.native)
    }

    private func nativeTextSelection(
        at containerPoint: CGPoint,
        prepared: TextKitPreparedLayoutState
    ) -> NSTextSelection? {
        let usageBounds = prepared.textLayoutManager.usageBoundsForTextContainer
        let minimumX = min(0, containerPoint.x)
        let minimumY = min(0, containerPoint.y)
        let maximumX = max(prepared.textContainer.size.width, containerPoint.x, 1)
        let maximumY = max(usageBounds.maxY, containerPoint.y, 1)
        let interactionBounds = CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        ).insetBy(dx: -1, dy: -1)
        return prepared.textLayoutManager.textSelectionNavigation.textSelections(
            interactingAt: containerPoint,
            inContainerAt: prepared.textLayoutManager.documentRange.location,
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
        layoutUTF16Count: Int,
        prepared: TextKitPreparedLayoutState
    ) -> NativeNavigationOutcome {
        var current = selection
        var receivedCandidate = false
        let attemptLimit = max(2, layoutUTF16Count + 1)

        for _ in 0..<attemptLimit {
            guard
                let candidate = prepared.textLayoutManager.textSelectionNavigation
                    .destinationSelection(
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
                let rawRange = nativeNSRange(for: nativeRange, prepared: prepared),
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
                let currentRawRange = nativeNSRange(for: currentRange, prepared: prepared),
                currentRawRange == rawRange,
                current.affinity == candidate.affinity
            {
                return .failure(.invalidCandidate)
            }
            current = candidate
        }
        return .failure(.invalidCandidate)
    }

    private func nativeNSRange(
        for range: NSTextRange,
        prepared: TextKitPreparedLayoutState
    ) -> NSRange? {
        let documentStart = prepared.textLayoutManager.documentRange.location
        let start = prepared.textContentStorage.offset(from: documentStart, to: range.location)
        let end = prepared.textContentStorage.offset(from: documentStart, to: range.endLocation)
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
        indexMap: TextKitTextIndexMap,
        prepared: TextKitPreparedLayoutState
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
                indexMap: indexMap,
                prepared: prepared
            )
        )
    }

    private func navigationContext(
        from nativeSelection: NSTextSelection,
        resolvedSelection: TextSelection,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle,
        indexMap: TextKitTextIndexMap,
        prepared: TextKitPreparedLayoutState
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
                indexMap: indexMap,
                prepared: prepared
            )
        )
    }

    private func validatedCaretInlineOffset(
        _ preferredInlineOffset: Double,
        resolvedSelection: TextSelection,
        request: BlockMeasureRequest,
        style: TextKitEditorStyle,
        indexMap: TextKitTextIndexMap,
        prepared: TextKitPreparedLayoutState
    ) -> Double? {
        guard
            resolvedSelection.rangeInSingleBlock?.isEmpty == true,
            let ordinaryCaretRect = caretRectWithoutLock(
                position: resolvedSelection.focus,
                request: request,
                style: style,
                indexMap: indexMap,
                prepared: prepared
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
            let hitSelection = nativeTextSelection(at: probePoint, prepared: prepared),
            let hitNativeRange = hitSelection.textRanges.only,
            let hitRawRange = nativeNSRange(for: hitNativeRange, prepared: prepared),
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
