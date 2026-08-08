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
        replaceTextBackend(textLayouter)
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
        // Same premise as a backend swap: the request is unchanged but the answer may
        // not be, and CaretGeometryKey cannot see that. Currently unreachable from any host,
        // so this is the cheap moment to close it rather than after a caller exists.
        cachedCaretGeometry = nil
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
        // Same premise as a backend swap: the request is unchanged but the answer may
        // not be, and CaretGeometryKey cannot see that. Currently unreachable from any host,
        // so this is the cheap moment to close it rather than after a caller exists.
        cachedCaretGeometry = nil
        blockLayout.invalidateAllMeasurements()
        return makeEditorUpdate(
            invalidation: EditorUpdateInvalidation(layoutGeometryChanged: true)
        )
    }
}
