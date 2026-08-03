import SlopadCoreModel

// MARK: - Invalidation

extension BlockLayout {
    package var isDirty: Bool {
        !dirtyInvalidation.blockIDs.isEmpty
            || dirtyInvalidation.visibleSequenceChanged
            || dirtyInvalidation.layoutGeometryChanged
    }

    package func hasPreparedLayout(for viewport: EditorViewport) -> Bool {
        currentRevision != nil && widthRevision == viewport.widthRevision
    }

    package mutating func markDirty(_ invalidation: BlockLayoutInvalidation) {
        dirtyInvalidation.formUnion(invalidation)
    }

    package mutating func advanceTextLayoutRevision() {
        textLayoutRevision += 1
        invalidateTextLayoutEnvironment()
    }

    package mutating func invalidateMeasurements(blockIDs: Set<BlockID>) {
        guard !blockIDs.isEmpty else { return }
        for blockID in blockIDs {
            cache.invalidate(blockID: blockID)
        }
        markDirty(BlockLayoutInvalidation(blockIDs: blockIDs, layoutGeometryChanged: true))
    }

    package mutating func invalidateAllMeasurements() {
        cache.invalidateAll()
        markDirty(BlockLayoutInvalidation(layoutGeometryChanged: true))
    }

    private mutating func invalidateTextLayoutEnvironment() {
        cache.invalidateAll()
        measurementsByBlockID.removeAll(keepingCapacity: true)
        markDirty(BlockLayoutInvalidation(layoutGeometryChanged: true))
    }
}
