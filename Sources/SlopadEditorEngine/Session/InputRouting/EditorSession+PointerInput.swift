import SlopadEditorBlockLayout
import SlopadCoreModel

// MARK: - Pointer Input

extension EditorSession {
    func handlePointerEvent(_ pointerEvent: EditorInputEvent.Pointer) -> EditorUpdate? {
        switch pointerEvent {
        case .focusText(let documentPoint, let viewport):
            return focusTextPointer(at: documentPoint, viewport: viewport)

        case .beginTextSelection(let documentPoint, let viewport):
            return beginTextPointerSelection(at: documentPoint, viewport: viewport)

        case .updateTextSelection(let documentPoint, let viewport):
            return updateTextPointerSelection(
                at: documentPoint,
                viewport: viewport
            )

        case .endTextSelection:
            return endTextPointerSelection()

        case .selectWordOrAllText(let documentPoint, let viewport):
            return selectWordOrAllTextFromPointer(at: documentPoint, viewport: viewport)

        case .selectBlock(let documentPoint, let region, let viewport):
            return selectBlockFromPointer(
                at: documentPoint,
                region: region,
                viewport: viewport
            )

        case .beginBlockDrag(let documentPoint, let viewport):
            return beginBlockDrag(at: documentPoint, viewport: viewport)

        case .updateBlockDrag(let documentPoint, let viewport):
            return updateBlockDrag(at: documentPoint, viewport: viewport)

        case .endBlockDrag(let documentPoint, let viewport):
            return endBlockDrag(at: documentPoint, viewport: viewport)

        case .cancelBlockDrag:
            return cancelBlockDrag()

        case .beginBlockSelectionRectangle(let documentPoint, let viewport):
            return beginBlockSelectionRectangle(at: documentPoint, viewport: viewport)

        case .updateBlockSelectionRectangle(let documentPoint, let viewport):
            return updateBlockSelectionRectangle(at: documentPoint, viewport: viewport)

        case .endBlockSelectionRectangle:
            return endBlockSelectionRectangle()

        case .extendBlockSelection(let documentPoint, let region, let viewport):
            return extendBlockSelectionFromPointer(
                at: documentPoint,
                region: region,
                viewport: viewport
            )

        case .endBlockSelection:
            return endBlockSelectionFromPointer()

        case .selectBlockRange(let anchor, let focus):
            return selectBlockRangeFromPointer(anchor: anchor, focus: focus)
        }
    }

    private func focusTextPointer(
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        clearPointerDragState()
        textDoubleClickSelection = nil
        if let update = focusText(at: documentPoint, viewport: viewport) {
            return update
        }
        return isEmptyDocumentArea(documentPoint, viewport: viewport)
            ? handlePointerEmptyArea()
            : nil
    }

    func handlePointerEmptyArea() -> EditorUpdate? {
        clearPointerDragState()
        textDoubleClickSelection = nil
        return handleSelectionChange(.inactive)
    }

    func isEmptyDocumentArea(
        _ documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> Bool {
        guard documentPoint.x >= 0, documentPoint.x <= viewport.width, documentPoint.y >= 0 else {
            return false
        }
        _ = preparedLayout(for: viewport)
        return blockLayout.blockID(atY: documentPoint.y) == nil
    }

    func clearPointerDragState() {
        blockSelectionDragAnchor = nil
        blockDrag = nil
        blockSelectionRectangle = nil
        textSelectionDragAnchor = nil
        textSelectionPendingOrigin = nil
    }
}
