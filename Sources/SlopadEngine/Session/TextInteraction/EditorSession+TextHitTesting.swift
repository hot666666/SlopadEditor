import SlopadCoreModel

// MARK: - EditorSession TextHitTesting

struct EditorSessionTextHitTest {
    let result: TextHitTestResult
    let request: BlockMeasureRequest
}

extension EditorSession {
    @discardableResult
    func focusText(
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> EditorUpdate? {
        guard let hit = textHitTest(at: documentPoint, viewport: viewport) else {
            return nil
        }
        let position = hit.result.position
        let selection = TextSelection(anchor: position, focus: position)
        let update = handleSelectionChange(.caret(position))
        recordTextNavigationContext(
            hit.result.navigationContext,
            for: selection,
            request: hit.request
        )
        return update
    }

    func textPosition(
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> TextPosition? {
        textHitTest(at: documentPoint, viewport: viewport)?.result.position
    }

    func textHitTest(
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> EditorSessionTextHitTest? {
        _ = preparedLayout(for: viewport)
        guard
            let rendered = renderedBlock(
                at: documentPoint,
                viewportWidth: viewport.width
            )
        else {
            return nil
        }

        let localPoint = EditorPoint(
            x: documentPoint.x - rendered.frame.x,
            y: documentPoint.y - rendered.frame.y
        )
        let request = rendered.textRender.measureRequest
        return validatedTextHitTest(
            textLayouter.textHitTest(at: localPoint, in: request),
            request: request
        )
    }

    func textPosition(
        in blockID: BlockID,
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> TextPosition? {
        textHitTest(
            in: blockID,
            at: documentPoint,
            viewport: viewport
        )?.result.position
    }

    func textHitTest(
        in blockID: BlockID,
        at documentPoint: EditorPoint,
        viewport: EditorViewport
    ) -> EditorSessionTextHitTest? {
        _ = preparedLayout(for: viewport)
        guard
            let rendered = renderedBlock(
                blockID: blockID,
                viewportWidth: viewport.width
            )
        else {
            return nil
        }

        let textFrame = rendered.textRender.frame
        let clampedPoint = EditorPoint(
            x: min(max(documentPoint.x, textFrame.minX), textFrame.maxX),
            y: min(max(documentPoint.y, textFrame.minY), textFrame.maxY)
        )
        let localPoint = EditorPoint(
            x: clampedPoint.x - rendered.frame.x,
            y: clampedPoint.y - rendered.frame.y
        )
        let request = rendered.textRender.measureRequest
        return validatedTextHitTest(
            textLayouter.textHitTest(at: localPoint, in: request),
            request: request
        )
    }

    func validatedTextHitTest(
        _ result: TextHitTestResult?,
        request: BlockMeasureRequest
    ) -> EditorSessionTextHitTest? {
        guard
            let result,
            result.position.blockID == request.blockID,
            (0...request.text.count).contains(result.position.offset)
        else { return nil }
        return EditorSessionTextHitTest(result: result, request: request)
    }
}
