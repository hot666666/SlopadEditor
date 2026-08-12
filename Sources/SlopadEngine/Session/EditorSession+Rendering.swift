import SlopadEditorBlockLayout
import SlopadCoreModel
import SlopadEditorModel

// MARK: - Rendering

extension EditorSession {
    public func render(in viewport: EditorViewport) -> EditorSessionSnapshot {
        let revision = preparedLayout(for: viewport)
        let visibleBlocks = renderedBlocks(
            geometries: blockLayout.visibleGeometries(
                yOffset: viewport.scrollY,
                viewportHeight: viewport.height
            ),
            document: editorModel.document,
            composition: composition,
            viewportWidth: viewport.width
        )
        let activeTextInput = makeActiveTextInput(in: visibleBlocks)
        let selectionPresentation = makeSelectionPresentation(
            in: visibleBlocks,
            activeTextInput: activeTextInput,
            viewport: viewport
        )
        return EditorSessionSnapshot(
            revision: revision,
            totalHeight: blockLayout.totalHeight,
            visibleBlocks: visibleBlocks,
            selection: activeEditorSelection,
            composition: composition,
            history: historyState,
            activeTextInput: activeTextInput,
            selectionPresentation: selectionPresentation,
            commandState: commandState(),
            slashCommand: slashCommandPresentation(activeTextInput: activeTextInput),
            blockDragState: blockDrag.map {
                EditorBlockDragState(dropIndicator: $0.dropIndicator)
            },
            blockSelectionRectangleState: blockSelectionRectangle.map {
                EditorBlockSelectionRectangleState(
                    rect: normalizedRect(from: $0.anchor, to: $0.current))
            }
        )
    }

    public func blockRevealFrame(for blockID: BlockID, viewport: EditorViewport) -> EditorRect? {
        _ = preparedLayout(for: viewport)
        return blockLayout.revealFrame(
            for: blockID,
            document: editorModel.document,
            composition: composition,
            viewport: viewport,
            textLayouter: blockMeasuring
        )
    }

    // MARK: - Active Text Input

    private func makeSelectionPresentation(
        in visibleBlocks: [EditorRenderedBlock],
        activeTextInput: EditorSessionActiveTextInputDescriptor?,
        viewport: EditorViewport
    ) -> EditorSelectionPresentation {
        invalidateBlockSelectionMembershipIfSelectionChanged()
        switch activeEditorSelection {
        case .text(let selection):
            return makeTextSelectionPresentation(
                selection,
                in: visibleBlocks,
                activeTextInput: activeTextInput,
                viewport: viewport
            )
        case .blocks(let selection):
            return makeBlockSelectionPresentation(
                selection,
                in: visibleBlocks,
                viewport: viewport
            )
        case .caret where composition != nil:
            return makeCompositionToolbarPresentation(
                activeTextInput: activeTextInput,
                viewport: viewport
            )
        case .inactive, .caret:
            return .empty
        }
    }

    private func makeCompositionToolbarPresentation(
        activeTextInput: EditorSessionActiveTextInputDescriptor?,
        viewport: EditorViewport
    ) -> EditorSelectionPresentation {
        guard
            case .text(let canonicalSelection) = editorModel.selection,
            let activeTextInput,
            let caretRect = activeTextInput.caretRect?.intersection(viewport.visibleRect)
        else { return .empty }
        let visibleBlockID = activeTextInput.renderDescriptor.measureRequest.blockID
        return EditorSelectionPresentation(
            visibleTextSelections: [],
            visibleBlockSelectionIDs: [],
            visibleBounds: caretRect,
            focusRect: caretRect,
            isAnchorVisible: canonicalSelection.anchor.blockID == visibleBlockID,
            isFocusVisible: canonicalSelection.focus.blockID == visibleBlockID
        )
    }

    private func makeTextSelectionPresentation(
        _ selection: TextSelection,
        in visibleBlocks: [EditorRenderedBlock],
        activeTextInput: EditorSessionActiveTextInputDescriptor?,
        viewport: EditorViewport
    ) -> EditorSelectionPresentation {
        guard
            let anchorIndex = blockLayout.visibleOrderIndex(of: selection.anchor.blockID),
            let focusIndex = blockLayout.visibleOrderIndex(of: selection.focus.blockID)
        else {
            return .empty
        }

        let anchorComesFirst =
            anchorIndex == focusIndex
            ? selection.anchor.offset <= selection.focus.offset
            : anchorIndex < focusIndex
        let start = anchorComesFirst ? selection.anchor : selection.focus
        let end = anchorComesFirst ? selection.focus : selection.anchor
        guard
            let startIndex = blockLayout.visibleOrderIndex(of: start.blockID),
            let endIndex = blockLayout.visibleOrderIndex(of: end.blockID)
        else {
            return .empty
        }

        let fragments = visibleBlocks.compactMap { rendered -> EditorVisibleTextSelection? in
            guard let index = blockLayout.visibleOrderIndex(of: rendered.id) else {
                return nil
            }
            guard index >= startIndex, index <= endIndex else { return nil }

            let contentLength = rendered.textRender.measureRequest.text.count
            let range: TextRange
            if start.blockID == end.blockID {
                range = TextRange(start.offset, end.offset).clamped(to: contentLength)
            } else if rendered.id == start.blockID {
                range = TextRange(start.offset, contentLength).clamped(to: contentLength)
            } else if rendered.id == end.blockID {
                range = TextRange(0, end.offset).clamped(to: contentLength)
            } else {
                range = TextRange(0, contentLength)
            }

            let rects: [EditorRect]
            if range.isEmpty {
                rects = []
            } else if start.blockID == end.blockID,
                activeTextInput?.renderDescriptor.measureRequest.blockID == rendered.id,
                activeTextInput?.selectedRange == range
            {
                rects = activeTextInput?.selectionRects ?? []
            } else {
                rects = textLayouter.selectionRects(
                    for: range,
                    in: rendered.textRender.measureRequest
                ).map { documentRect($0, in: rendered.textRender) }
            }
            let blockTintRect =
                rendered.kind.usesAtomicSelectionTint
                ? rendered.frame
                : nil
            return EditorVisibleTextSelection(
                blockID: rendered.id,
                range: range,
                rects: rects,
                blockTintRect: blockTintRect
            )
        }
        let viewportRect = viewport.visibleRect
        let visibleGeometry = fragments.flatMap { fragment in
            fragment.rects + [fragment.blockTintRect].compactMap { $0 }
        }.compactMap { $0.intersection(viewportRect) }
        let focusFragment = fragments.first { $0.blockID == selection.focus.blockID }
        let focusGeometry =
            focusFragment.map { fragment in
                fragment.rects + [fragment.blockTintRect].compactMap { $0 }
            } ?? []
        let visibleFocusGeometry = focusGeometry.compactMap { $0.intersection(viewportRect) }
        let focusRect =
            anchorComesFirst
            ? visibleFocusGeometry.last
            : visibleFocusGeometry.first
        let visibleIDs = Set(visibleBlocks.map(\.id))
        return EditorSelectionPresentation(
            visibleTextSelections: fragments,
            visibleBlockSelectionIDs: [],
            visibleBounds: union(of: visibleGeometry),
            focusRect: focusRect,
            isAnchorVisible: visibleIDs.contains(selection.anchor.blockID),
            isFocusVisible: visibleIDs.contains(selection.focus.blockID)
        )
    }

    private func makeBlockSelectionPresentation(
        _ selection: BlockSelection,
        in visibleBlocks: [EditorRenderedBlock],
        viewport: EditorViewport
    ) -> EditorSelectionPresentation {
        let selectedVisibleBlocks: [EditorRenderedBlock]
        if let firstID = selection.blockIDs.first,
            let lastID = selection.blockIDs.last,
            let firstIndex = blockLayout.visibleOrderIndex(of: firstID),
            let lastIndex = blockLayout.visibleOrderIndex(of: lastID),
            abs(lastIndex - firstIndex) + 1 == selection.blockIDs.count
        {
            let lowerBound = min(firstIndex, lastIndex)
            let upperBound = max(firstIndex, lastIndex)
            selectedVisibleBlocks = visibleBlocks.filter { block in
                guard let index = blockLayout.visibleOrderIndex(of: block.id) else { return false }
                return index >= lowerBound && index <= upperBound
            }
        } else {
            // Non-contiguous structural selections are uncommon command results such as
            // pasted roots. Session retains one exact-selection membership index so stable
            // viewport renders stay O(V) without rebuilding or revisiting the full span.
            let selectedIDs = blockSelectionMembership(for: selection)
            selectedVisibleBlocks = visibleBlocks.filter { selectedIDs.contains($0.id) }
        }
        let viewportRect = viewport.visibleRect
        let visibleFrames = selectedVisibleBlocks.compactMap {
            $0.frame.intersection(viewportRect)
        }
        let focusRect = selectedVisibleBlocks.first { $0.id == selection.focus }?.frame
            .intersection(viewportRect)
        let visibleIDs = Set(selectedVisibleBlocks.map(\.id))
        return EditorSelectionPresentation(
            visibleTextSelections: [],
            visibleBlockSelectionIDs: visibleIDs,
            visibleBounds: union(of: visibleFrames),
            focusRect: focusRect,
            isAnchorVisible: visibleIDs.contains(selection.anchor),
            isFocusVisible: visibleIDs.contains(selection.focus)
        )
    }

    private func blockSelectionMembership(
        for selection: BlockSelection
    ) -> Set<BlockID> {
        let selectionIdentity = editorModel.selectionIdentity
        if let cachedBlockSelectionMembership,
            cachedBlockSelectionMembership.selectionIdentity == selectionIdentity
        {
            return cachedBlockSelectionMembership.blockIDs
        }
        let blockIDs = Set(selection.blockIDs)
        cachedBlockSelectionMembership = BlockSelectionMembershipCache(
            selectionIdentity: selectionIdentity,
            blockIDs: blockIDs
        )
        blockSelectionMembershipRebuildCount += 1
        blockSelectionMembershipVisitedIDCount += selection.blockIDs.count
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            benchmarkMetrics.blockSelectionMembershipRebuildCount += 1
            benchmarkMetrics.blockSelectionMembershipVisitedIDCount += selection.blockIDs.count
        #endif
        return blockIDs
    }

    private func invalidateBlockSelectionMembershipIfSelectionChanged() {
        guard let cachedBlockSelectionMembership else { return }
        guard cachedBlockSelectionMembership.selectionIdentity != editorModel.selectionIdentity
        else { return }
        self.cachedBlockSelectionMembership = nil
    }

    private func union(of rects: [EditorRect]) -> EditorRect? {
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { result, rect in
            let minX = min(result.minX, rect.minX)
            let minY = min(result.minY, rect.minY)
            let maxX = max(result.maxX, rect.maxX)
            let maxY = max(result.maxY, rect.maxY)
            return EditorRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            )
        }
    }

    private func makeActiveTextInput(
        in visibleBlocks: [EditorRenderedBlock]
    ) -> EditorSessionActiveTextInputDescriptor? {
        guard
            let activeSelection = activeTextSelection(),
            let rendered = visibleBlocks.first(where: { $0.id == activeSelection.position.blockID })
        else {
            return nil
        }

        let contentLength = rendered.textRender.measureRequest.text.count
        let selectedRange = activeSelection.range.clamped(to: contentLength)
        let focusOffset = max(0, min(activeSelection.position.offset, contentLength))
        let navigationContext = activeTextNavigationSelection().flatMap {
            textNavigationContext(for: $0, request: rendered.textRender.measureRequest)
        }
        let caretPosition = TextPosition(
            blockID: rendered.textRender.measureRequest.blockID,
            offset: focusOffset,
            affinity: activeSelection.position.affinity
        )

        let geometry = caretGeometry(
            key: CaretGeometryKey(
                measureRequest: rendered.textRender.measureRequest,
                frame: rendered.textRender.frame,
                selectedRange: selectedRange,
                caretPosition: caretPosition,
                navigationContext: navigationContext
            ),
            renderDescriptor: rendered.textRender
        )

        return EditorSessionActiveTextInputDescriptor(
            selectedRange: selectedRange,
            focusOffset: focusOffset,
            focusAffinity: activeSelection.position.affinity,
            navigationContext: navigationContext,
            renderDescriptor: rendered.textRender,
            caretRect: geometry.caretRect,
            selectionRects: geometry.selectionRects
        )
    }

    /// Everything the caret and selection rectangles depend on.
    struct CaretGeometryKey: Hashable {
        let measureRequest: BlockMeasureRequest
        let frame: EditorRect
        let selectedRange: TextRange
        let caretPosition: TextPosition
        let navigationContext: TextNavigationContext?
    }

    /// Resolves caret and selection geometry, reusing the previous answer when nothing it
    /// depends on has changed.
    ///
    /// The adapter renders repeatedly while the surface converges — up to 32 passes as the
    /// canvas resizes and a scrollbar appears — and only paints once at the end. Without this,
    /// selecting across a long block would walk every line fragment on each of those passes
    /// and throw away all but the last result. Before this change the walk happened once per
    /// paint, so recomputing per render would have been a regression.
    private func caretGeometry(
        key: CaretGeometryKey,
        renderDescriptor: EditorTextRenderDescriptor
    ) -> (caretRect: EditorRect?, selectionRects: [EditorRect]) {
        if let cached = cachedCaretGeometry, cached.key == key {
            return (cached.caretRect, cached.selectionRects)
        }

        let caretRect = textLayouter.caretRect(
            for: key.caretPosition,
            navigationContext: key.navigationContext,
            in: key.measureRequest
        ).map { documentRect($0, in: renderDescriptor) }

        let selectionRects =
            key.selectedRange.isEmpty
            ? []
            : textLayouter.selectionRects(for: key.selectedRange, in: key.measureRequest)
                .map { documentRect($0, in: renderDescriptor) }

        cachedCaretGeometry = (key, caretRect, selectionRects)
        return (caretRect, selectionRects)
    }

    /// Line fragment rectangles for a laid-out block, in document coordinates.
    ///
    /// Answers "does this point land on text" for a caller deciding between starting a text
    /// selection and starting a block-selection rectangle. The question is about laid-out
    /// text, so it is resolved here rather than by the adapter reaching for the backend; the
    /// caller still owns its own hit tolerance.
    public func textLineFragmentRects(
        in renderDescriptor: EditorTextRenderDescriptor
    ) -> [EditorRect] {
        textLayouter.lineFragments(for: renderDescriptor.measureRequest)
            .map { documentRect($0.rect, in: renderDescriptor) }
    }

    /// Converts a rect the backend reports inside a block's text into document coordinates.
    ///
    /// The backend answers relative to the laid-out text, which sits at an offset inside the
    /// block's frame; `textFrame` reports that offset.
    private func documentRect(
        _ localRect: EditorRect,
        in descriptor: EditorTextRenderDescriptor
    ) -> EditorRect {
        let textFrame = textLayouter.textFrame(
            for: descriptor.measureRequest, measuredHeight: nil)
        return EditorRect(
            x: localRect.x + descriptor.frame.x - textFrame.x,
            y: localRect.y + descriptor.frame.y - textFrame.y,
            width: localRect.width,
            height: localRect.height
        )
    }
}

struct BlockSelectionMembershipCache {
    let selectionIdentity: EditorSelectionIdentity
    let blockIDs: Set<BlockID>
}

extension BlockKind {
    fileprivate var usesAtomicSelectionTint: Bool {
        switch self {
        case .divider:
            return true
        default:
            return false
        }
    }
}
