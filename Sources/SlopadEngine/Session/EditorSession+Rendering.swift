import SlopadBlockLayout
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
        return EditorSessionSnapshot(
            revision: revision,
            totalHeight: blockLayout.totalHeight,
            visibleBlocks: visibleBlocks,
            selection: activeEditorSelection,
            composition: composition,
            history: historyState,
            activeTextInput: makeActiveTextInput(in: visibleBlocks),
            blockDragState: blockDrag.map {
                EditorBlockDragState(dropIndicator: $0.dropIndicator)
            },
            blockSelectionRectangleState: blockSelectionRectangle.map {
                EditorBlockSelectionRectangleState(rect: normalizedRect(from: $0.anchor, to: $0.current))
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
