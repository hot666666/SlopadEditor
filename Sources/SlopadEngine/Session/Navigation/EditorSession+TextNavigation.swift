import SlopadCoreModel

// MARK: - Text Navigation

struct EditorSessionTextNavigationRuntimeContext: Equatable {
    let selection: TextSelection
    let request: BlockMeasureRequest
    let backendContext: TextNavigationContext
}

extension EditorSession {
    func activeTextNavigationSelection() -> TextSelection? {
        switch activeEditorSelection {
        case .caret(let position):
            return TextSelection(anchor: position, focus: position)

        case .text(let selection) where selection.isSingleBlock:
            return selection

        case .inactive, .blocks, .text:
            return nil
        }
    }

    func textNavigationRequest(
        for selection: TextSelection,
        viewport: EditorViewport
    ) -> BlockMeasureRequest? {
        guard
            selection.isSingleBlock,
            selection.anchor.blockID == selection.focus.blockID
        else { return nil }

        _ = preparedLayout(for: viewport)
        return renderedBlock(
            blockID: selection.focus.blockID,
            viewportWidth: viewport.width
        )?.textRender.measureRequest
    }

    func textNavigationRequest(
        for position: TextPosition,
        viewport: EditorViewport
    ) -> BlockMeasureRequest? {
        textNavigationRequest(
            for: TextSelection(anchor: position, focus: position),
            viewport: viewport
        )
    }

    func applyTextNavigationSelection(
        _ resolvedSelection: TextSelection,
        context: TextNavigationContext?,
        extending: Bool,
        preservingAnchor anchor: TextPosition? = nil,
        request: BlockMeasureRequest
    ) -> EditorUpdate? {
        guard isValidTextNavigationSelection(resolvedSelection, in: request) else {
            return nil
        }
        if extending {
            guard anchor != nil else { return nil }
        } else {
            guard
                anchor == nil,
                resolvedSelection.rangeInSingleBlock?.isEmpty == true
            else { return nil }
        }
        let selection = anchor.map {
            TextSelection(anchor: $0, focus: resolvedSelection.focus)
        } ?? resolvedSelection
        guard isValidTextNavigationSelection(selection, in: request) else { return nil }

        let nextSelection: EditorSelection =
            selection.rangeInSingleBlock?.isEmpty == true
            ? .caret(selection.focus)
            : .text(selection)
        let validatedContext = context.flatMap {
            $0.preferredInlineOffset.isFinite
                && ($0.caretInlineOffset?.isFinite ?? true)
                ? $0
                : nil
        }
        let nextRuntimeContext = validatedContext.map {
            EditorSessionTextNavigationRuntimeContext(
                selection: selection,
                request: request,
                backendContext: $0
            )
        }
        guard
            activeEditorSelection != nextSelection
                || textNavigationRuntimeContext != nextRuntimeContext
        else { return nil }

        let update = activeEditorSelection == nextSelection
            ? makeEditorUpdate(invalidation: EditorUpdateInvalidation())
            : handleSelectionChange(nextSelection)
        textNavigationRuntimeContext = nextRuntimeContext
        return update
    }

    func textNavigationContext(
        for selection: TextSelection,
        request: BlockMeasureRequest
    ) -> TextNavigationContext? {
        guard
            let runtimeContext = textNavigationRuntimeContext,
            runtimeContext.selection == selection,
            runtimeContext.request == request
        else { return nil }
        return runtimeContext.backendContext
    }

    func recordTextNavigationContext(
        _ context: TextNavigationContext?,
        for selection: TextSelection,
        request: BlockMeasureRequest
    ) {
        guard
            let context,
            context.preferredInlineOffset.isFinite,
            context.caretInlineOffset?.isFinite ?? true
        else {
            textNavigationRuntimeContext = nil
            return
        }
        textNavigationRuntimeContext = EditorSessionTextNavigationRuntimeContext(
            selection: selection,
            request: request,
            backendContext: context
        )
    }

    private func isValidTextNavigationSelection(
        _ selection: TextSelection,
        in request: BlockMeasureRequest
    ) -> Bool {
        selection.isSingleBlock
            && selection.anchor.blockID == request.blockID
            && selection.focus.blockID == request.blockID
            && (0...request.text.count).contains(selection.anchor.offset)
            && (0...request.text.count).contains(selection.focus.offset)
    }

    func isValidTextBackendRange(
        _ range: TextRange,
        in request: BlockMeasureRequest
    ) -> Bool {
        range.lowerBound >= 0
            && range.lowerBound <= range.upperBound
            && range.upperBound <= request.text.count
    }

    func isValidTextDeletionRange(
        _ range: TextRange,
        for selection: TextSelection,
        direction: TextNavigationDirection,
        destination: TextNavigationDestination,
        in request: BlockMeasureRequest
    ) -> Bool {
        guard
            isValidTextBackendRange(range, in: request),
            isValidTextNavigationSelection(selection, in: request),
            let selectedRange = selection.rangeInSingleBlock
        else { return false }
        guard selectedRange.isEmpty else { return range == selectedRange }

        guard destination == .word else { return true }
        switch direction {
        case .backward:
            return range.upperBound == selection.focus.offset
        case .forward:
            return range.lowerBound == selection.focus.offset
        case .left, .right:
            return true
        }
    }
}
