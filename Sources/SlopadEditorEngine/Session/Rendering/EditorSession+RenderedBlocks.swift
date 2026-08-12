import SlopadEditorBlockLayout
import SlopadEditorCoreModel

// MARK: - EditorSession RenderedBlocks

extension EditorSession {
    func renderedBlocks(
        geometries: [BlockLayoutGeometry],
        document: Document,
        composition: TextComposition?,
        viewportWidth: Double
    ) -> [EditorRenderedBlock] {
        guard !geometries.isEmpty else { return [] }

        var output: [EditorRenderedBlock] = []
        output.reserveCapacity(geometries.count)
        for geometry in geometries {
            if let rendered = renderedBlock(
                geometry: geometry,
                document: document,
                composition: composition,
                viewportWidth: viewportWidth
            ) {
                output.append(rendered)
            }
        }
        return output
    }

    func renderedBlock(
        blockID: BlockID,
        viewportWidth: Double
    ) -> EditorRenderedBlock? {
        guard let geometry = blockLayout.blockGeometry(for: blockID) else {
            return nil
        }
        return renderedBlock(
            geometry: geometry,
            document: editorModel.document,
            composition: composition,
            viewportWidth: viewportWidth
        )
    }

    func renderedBlock(
        at documentPoint: EditorPoint,
        viewportWidth: Double
    ) -> EditorRenderedBlock? {
        guard
            documentPoint.x >= 0,
            documentPoint.x <= viewportWidth,
            let blockID = blockLayout.blockID(atY: documentPoint.y)
        else {
            return nil
        }
        return renderedBlock(
            blockID: blockID,
            viewportWidth: viewportWidth
        )
    }

    private func renderedBlock(
        geometry: BlockLayoutGeometry,
        document: Document,
        composition: TextComposition?,
        viewportWidth: Double
    ) -> EditorRenderedBlock? {
        let blockID = geometry.blockID
        guard
            let block = blockLayout.effectiveBlock(
                for: blockID,
                document: document,
                composition: composition
            )
        else {
            return nil
        }

        let frame = geometry.frame(width: viewportWidth)
        let measureRequest = BlockMeasureRequest(
            block: block,
            depth: geometry.depth,
            availableWidth: viewportWidth
        )
        let textFrame =
            textLayouter
            .textFrame(for: measureRequest, measuredHeight: frame.height)
            .offsetBy(dx: frame.x, dy: frame.y)

        return EditorRenderedBlock(
            markerKind: geometry.markerKind,
            frame: frame,
            textRender: EditorTextRenderDescriptor(
                measureRequest: measureRequest,
                frame: textFrame
            )
        )
    }
}
