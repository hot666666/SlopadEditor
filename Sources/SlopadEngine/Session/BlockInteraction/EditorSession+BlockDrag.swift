import SlopadEditorBlockLayout
import SlopadCoreModel
import SlopadEditorDocumentModel

// MARK: - Block Drag

extension EditorSession {
    func beginBlockDrag(
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard
            case .blocks(let blockSelection) = editorModel.selection,
            let hit = hitTest(documentPoint: documentPoint, region: .gutter, viewport: viewport),
            blockSelection.blockIDs.contains(hit.blockID)
        else {
            return nil
        }
        clearPointerDragState()
        textDoubleClickSelection = nil
        blockDrag = (
            blockIDs: blockSelection.blockIDs,
            dropTarget: nil,
            dropIndicator: nil
        )
        return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
    }

    func updateBlockDrag(
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard let drag = blockDrag else { return nil }
        let resolvedTarget = blockDropTarget(
            at: documentPoint, viewport: viewport, blockIDs: drag.blockIDs)
        blockDrag = (
            blockIDs: drag.blockIDs,
            dropTarget: resolvedTarget?.target,
            dropIndicator: resolvedTarget?.indicator
        )
        return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
    }

    func endBlockDrag(
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard let drag = blockDrag else { return nil }
        let resolvedTarget = blockDropTarget(
            at: documentPoint, viewport: viewport, blockIDs: drag.blockIDs)
        let dropTarget = resolvedTarget?.target ?? drag.dropTarget
        blockDrag = nil

        guard let target = dropTarget else {
            return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
        }
        let selection = BlockSelection(blockIDs: drag.blockIDs)
        return handleCommand(.moveBlockSelection(selection, target: target))
    }

    func cancelBlockDrag() -> EditorUpdate? {
        blockDrag = nil
        return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
    }

    // MARK: - Drop Target Resolution

    private func blockDropTarget(
        at documentPoint: EditorPoint,
        viewport: EditorViewport,
        blockIDs: [BlockID]
    ) -> (target: BlockDropTarget, indicator: EditorRect)? {
        _ = preparedLayout(for: viewport)
        guard
            let dropTarget = blockLayout.blockDropTarget(
                atY: documentPoint.y,
                viewportWidth: viewport.width
            ),
            !editorModel.document.hasAncestorOrSelf(
                in: Set(blockIDs),
                of: dropTarget.target.blockID
            )
        else {
            return nil
        }
        return dropTarget
    }
}
