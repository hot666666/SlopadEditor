import SlopadCoreModel

// MARK: - Layout Invalidation

extension EditorSession {
    /// Replaces the coherent text-layout backend and invalidates every derived measurement.
    ///
    /// A platform adapter that also owns text drawing must replace its drawing backend from
    /// the same configuration before publishing the next rendered surface.
    @discardableResult
    public func replaceTextLayoutBackend(
        with textLayouter: any BlockTextLayoutProtocol
    ) -> EditorUpdate {
        self.textLayouter = textLayouter
        textNavigationRuntimeContext = nil
        if let blockDrag {
            self.blockDrag = (
                blockIDs: blockDrag.blockIDs,
                dropTarget: nil,
                dropIndicator: nil
            )
        }
        blockLayout.advanceTextLayoutRevision()
        return makeEditorUpdate(
            invalidation: EditorUpdateInvalidation(layoutGeometryChanged: true)
        )
    }

    @discardableResult
    func invalidateLayoutMeasurements(blockIDs: Set<BlockID>) -> EditorUpdate {
        guard !blockIDs.isEmpty else {
            return makeEditorUpdate(invalidation: EditorUpdateInvalidation())
        }
        blockLayout.invalidateMeasurements(blockIDs: blockIDs)
        return makeEditorUpdate(
            invalidation: EditorUpdateInvalidation(blockIDs: blockIDs, layoutGeometryChanged: true)
        )
    }

    @discardableResult
    func invalidateAllLayoutMeasurements() -> EditorUpdate {
        blockLayout.invalidateAllMeasurements()
        return makeEditorUpdate(
            invalidation: EditorUpdateInvalidation(layoutGeometryChanged: true)
        )
    }
}
