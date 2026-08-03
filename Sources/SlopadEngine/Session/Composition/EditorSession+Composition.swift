import SlopadBlockLayout
import SlopadCoreModel
import SlopadEditorModel

// MARK: - Composition

extension EditorSession {
    func canReceiveCompositionInput(blockID: BlockID) -> Bool {
        canRouteTextCommand()
            && activeTextPosition()?.blockID == blockID
    }

    func commitCompositionForImplicitExitIfNeeded(
        compatibleWith selection: EditorSelection
    ) -> (previousSelection: EditorSelection?, invalidation: EditorUpdateInvalidation) {
        guard
            let currentComposition = composition,
            !selection.isCompatibleWithComposition(blockID: currentComposition.blockID)
        else {
            return (previousSelection: nil, invalidation: EditorUpdateInvalidation())
        }

        let previousSelection = activeEditorSelection
        let clearInvalidation = clearComposition(currentComposition)
        let commit = commitCompositionText(currentComposition)
        var invalidation = clearInvalidation
        invalidation.formUnion(commit.invalidation)
        return (
            previousSelection: previousSelection,
            invalidation: invalidation
        )
    }

    func setComposition(_ newComposition: TextComposition) -> EditorUpdate {
        let previousSelection = activeEditorSelection
        recordCompositionRevision(newComposition.compositionRevision)
        var blockIDs: Set<BlockID> = [newComposition.blockID]
        if let composition {
            blockIDs.insert(composition.blockID)
        }
        composition = newComposition
        compositionSelection = defaultCompositionSelection(for: newComposition)
        textNavigationRuntimeContext = nil
        let layoutInvalidation = BlockLayoutInvalidation(
            blockIDs: blockIDs,
            layoutGeometryChanged: true
        )
        blockLayout.markDirty(layoutInvalidation)
        let invalidation = EditorUpdateInvalidation(
            blockIDs: blockIDs,
            layoutGeometryChanged: true
        )
        return makeEditorUpdate(
            invalidation: invalidation,
            previousSelection: previousSelection
        )
    }

    func endComposition(commit: Bool) -> EditorUpdate {
        guard let currentComposition = composition else {
            return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
        }
        let previousSelection = activeEditorSelection
        let clearInvalidation = clearComposition(currentComposition)

        guard commit else {
            return makeEditorUpdate(
                invalidation: clearInvalidation,
                previousSelection: previousSelection
            )
        }

        let committed = commitCompositionText(currentComposition)
        var invalidation = clearInvalidation
        invalidation.formUnion(committed.invalidation)
        return makeEditorUpdate(
            invalidation: invalidation,
            previousSelection: previousSelection
        )
    }

    func commitCompositionAndApply(
        _ command: EditorCommand,
        effectiveSelection: TextSelection
    ) -> EditorUpdate? {
        guard
            let currentComposition = composition,
            let normalizedSelection = normalizedCompositionSelection(
                effectiveSelection,
                for: currentComposition
            ),
            normalizedSelection == effectiveSelection
        else { return nil }

        let previousSelection = activeEditorSelection
        guard
            let result = editorModel.apply([
                .command(
                    .replaceText(
                        blockID: currentComposition.blockID,
                        range: currentComposition.replacementRange,
                        text: currentComposition.text
                    )
                ),
                .replaceSelection(editorSelection(for: effectiveSelection)),
                .command(command),
            ])
        else { return nil }

        var invalidation = clearComposition(currentComposition)
        invalidation.formUnion(markLayoutDirty(for: result.change))
        return makeEditorUpdate(
            invalidation: invalidation,
            previousSelection: previousSelection
        )
    }

    func clearComposition(
        _ currentComposition: TextComposition
    ) -> EditorUpdateInvalidation {
        composition = nil
        compositionSelection = nil
        textNavigationRuntimeContext = nil
        let blockIDs: Set<BlockID> = [currentComposition.blockID]
        let layoutInvalidation = BlockLayoutInvalidation(
            blockIDs: blockIDs,
            layoutGeometryChanged: true
        )
        blockLayout.markDirty(layoutInvalidation)
        return EditorUpdateInvalidation(blockIDs: blockIDs, layoutGeometryChanged: true)
    }

    private func commitCompositionText(
        _ currentComposition: TextComposition
    ) -> (previousSelection: EditorSelection?, invalidation: EditorUpdateInvalidation) {
        applyCommandForUpdate(
            .replaceText(
                blockID: currentComposition.blockID,
                range: currentComposition.replacementRange,
                text: currentComposition.text
            )
        )
    }

    func normalizedCompositionSelection(
        _ selection: TextSelection,
        for composition: TextComposition
    ) -> TextSelection? {
        guard
            selection.isSingleBlock,
            selection.anchor.blockID == composition.blockID,
            selection.focus.blockID == composition.blockID,
            let textLength = effectiveTextLength(for: composition)
        else { return nil }

        return TextSelection(
            anchor: clampedPosition(selection.anchor, to: textLength),
            focus: clampedPosition(selection.focus, to: textLength)
        )
    }

    private func defaultCompositionSelection(
        for composition: TextComposition
    ) -> TextSelection? {
        guard let block = editorModel.document.block(composition.blockID) else { return nil }
        let replacementRange = composition.replacementRange.clamped(to: block.content.length)
        let position = TextPosition(
            blockID: composition.blockID,
            offset: replacementRange.lowerBound + composition.text.count
        )
        return TextSelection(anchor: position, focus: position)
    }

    func effectiveTextLength(for composition: TextComposition) -> Int? {
        guard let block = editorModel.document.block(composition.blockID) else { return nil }
        let replacementRange = composition.replacementRange.clamped(to: block.content.length)
        return block.content.length - replacementRange.length + composition.text.count
    }

    private func clampedPosition(_ position: TextPosition, to textLength: Int) -> TextPosition {
        TextPosition(
            blockID: position.blockID,
            offset: max(0, min(position.offset, textLength)),
            affinity: position.affinity
        )
    }
}
