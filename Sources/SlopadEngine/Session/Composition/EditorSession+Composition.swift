import SlopadBlockLayout
import SlopadCoreModel
import SlopadEditorModel

// MARK: - Composition

extension EditorSession {
    func canReceiveCompositionInput(blockID: BlockID) -> Bool {
        canRouteTextCommand()
            && activeTextPosition()?.blockID == blockID
    }

    func beginComposition(
        blockID: BlockID,
        replacementRange: TextRange,
        text: String
    ) -> EditorUpdate? {
        guard composition == nil, compositionTransaction == nil else { return nil }

        var transaction = editorModel.beginLiveTransaction()
        let result = editorModel.apply(
            .replaceCompositionText(
                blockID: blockID,
                range: replacementRange,
                text: text
            ),
            in: &transaction
        )
        guard result.isApplied, let markedRange = liveMarkedRange(for: text) else { return nil }

        compositionTransaction = transaction
        return setLiveComposition(
            nextTextComposition(
                blockID: markedRange.blockID,
                replacementRange: markedRange.range,
                text: text
            ),
            change: result.outcome?.change,
            previousSelection: result.outcome?.selectionBefore
        )
    }

    func updateComposition(
        blockID: BlockID,
        replacementRange: TextRange,
        text: String
    ) -> EditorUpdate? {
        guard
            let currentComposition = composition,
            currentComposition.blockID == blockID,
            var transaction = compositionTransaction
        else { return nil }

        let result = editorModel.apply(
            .replaceCompositionText(
                blockID: blockID,
                range: replacementRange,
                text: text
            ),
            in: &transaction
        )
        guard result.isApplied, let markedRange = liveMarkedRange(for: text) else { return nil }

        compositionTransaction = transaction
        return setLiveComposition(
            nextTextComposition(
                blockID: markedRange.blockID,
                replacementRange: markedRange.range,
                text: text
            ),
            change: result.outcome?.change,
            previousSelection: result.outcome?.selectionBefore
        )
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
        let invalidation = finishComposition(applyingCommittedInputRules: true)
        return (previousSelection: previousSelection, invalidation: invalidation)
    }

    func endComposition(commit: Bool) -> EditorUpdate {
        guard composition != nil else {
            return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
        }
        let previousSelection = activeEditorSelection
        // AppKit reports the actual post-callback marked content before ending the lifecycle.
        // Both commit and cancel therefore close the live history group; cancel does not
        // restore a shadow document that AppKit no longer presents.
        let invalidation = finishComposition(applyingCommittedInputRules: commit)
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
            normalizedSelection == effectiveSelection,
            var transaction = compositionTransaction
        else { return nil }

        let previousSelection = activeEditorSelection
        var invalidation = applyCommittedCompositionText(
            currentComposition,
            transaction: &transaction
        )
        let result = editorModel.apply(
            [
                .replaceSelection(editorSelection(for: effectiveSelection)),
                .command(command),
            ],
            in: &transaction
        )
        guard result.isApplied else { return nil }
        invalidation.formUnion(markLayoutDirtyWithoutCommit(for: result.outcome?.change))

        compositionTransaction = transaction
        invalidation.formUnion(clearComposition(currentComposition))
        commitCompositionHistory()
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

    func effectiveTextLength(for composition: TextComposition) -> Int? {
        editorModel.document.block(composition.blockID)?.content.length
    }

    private func setLiveComposition(
        _ newComposition: TextComposition,
        change: EditorChange?,
        previousSelection: EditorSelection?
    ) -> EditorUpdate {
        recordCompositionRevision(newComposition.compositionRevision)
        var blockIDs: Set<BlockID> = [newComposition.blockID]
        if let composition {
            blockIDs.insert(composition.blockID)
        }
        composition = newComposition
        compositionSelection = defaultCompositionSelection(for: newComposition)
        textNavigationRuntimeContext = nil

        var invalidation = markLayoutDirtyWithoutCommit(for: change)
        invalidation.formUnion(
            EditorUpdateInvalidation(
                blockIDs: blockIDs,
                layoutGeometryChanged: true
            )
        )
        blockLayout.markDirty(
            BlockLayoutInvalidation(
                blockIDs: blockIDs,
                layoutGeometryChanged: true
            )
        )
        return makeEditorUpdate(
            invalidation: invalidation,
            previousSelection: previousSelection
        )
    }

    private func finishComposition(
        applyingCommittedInputRules: Bool
    ) -> EditorUpdateInvalidation {
        guard let currentComposition = composition else {
            return EditorUpdateInvalidation()
        }

        var invalidation = EditorUpdateInvalidation()
        if applyingCommittedInputRules, var transaction = compositionTransaction {
            invalidation.formUnion(
                applyCommittedCompositionText(
                    currentComposition,
                    transaction: &transaction
                )
            )
            compositionTransaction = transaction
        }
        invalidation.formUnion(clearComposition(currentComposition))
        commitCompositionHistory()
        return invalidation
    }

    private func applyCommittedCompositionText(
        _ currentComposition: TextComposition,
        transaction: inout EditorLiveTransaction
    ) -> EditorUpdateInvalidation {
        let result = editorModel.apply(
            .replaceText(
                blockID: currentComposition.blockID,
                range: currentComposition.replacementRange,
                text: currentComposition.text
            ),
            in: &transaction
        )
        return markLayoutDirtyWithoutCommit(for: result.outcome?.change)
    }

    private func commitCompositionHistory() {
        guard let transaction = compositionTransaction else { return }
        compositionTransaction = nil
        guard let outcome = editorModel.commit(transaction) else { return }
        if outcome.change.documentChanged {
            recordDocumentChange()
        }
    }

    private func markLayoutDirtyWithoutCommit(
        for change: EditorChange?
    ) -> EditorUpdateInvalidation {
        markLayoutDirty(for: change, recordsCommittedDocumentChange: false)
    }

    private func liveMarkedRange(for text: String) -> (blockID: BlockID, range: TextRange)? {
        guard case .caret(let position) = editorModel.selection else { return nil }
        let lowerBound = position.offset - text.count
        guard lowerBound >= 0 else { return nil }
        return (
            position.blockID,
            TextRange(lowerBound, position.offset)
        )
    }

    private func defaultCompositionSelection(
        for composition: TextComposition
    ) -> TextSelection {
        let position = TextPosition(
            blockID: composition.blockID,
            offset: composition.replacementRange.upperBound
        )
        return TextSelection(anchor: position, focus: position)
    }

    private func clampedPosition(_ position: TextPosition, to textLength: Int) -> TextPosition {
        TextPosition(
            blockID: position.blockID,
            offset: max(0, min(position.offset, textLength)),
            affinity: position.affinity
        )
    }
}
