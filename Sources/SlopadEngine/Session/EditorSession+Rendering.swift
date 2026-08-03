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
            textLayouter: textLayouter
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
        return EditorSessionActiveTextInputDescriptor(
            selectedRange: activeSelection.range.clamped(to: contentLength),
            focusOffset: max(0, min(activeSelection.position.offset, contentLength)),
            focusAffinity: activeSelection.position.affinity,
            navigationContext: activeTextNavigationSelection().flatMap {
                textNavigationContext(
                    for: $0,
                    request: rendered.textRender.measureRequest
                )
            },
            renderDescriptor: rendered.textRender
        )
    }
}
