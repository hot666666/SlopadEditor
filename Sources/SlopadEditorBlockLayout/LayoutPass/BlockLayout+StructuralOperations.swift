import SlopadCoreModel

// MARK: - Structural Operations

extension BlockLayout {
    mutating func applyStructuralOperations(
        document: Document,
        composition: TextComposition?,
        viewport: EditorViewport,
        textLayouter: any BlockMeasuring
    ) -> EditorSnapshotRevision? {
        guard
            let nextVisibleIndex = visibleIndex,
            var nextMarkerSequence = markerSequence
        else {
            return nil
        }
        visibleIndex = nil
        markerSequence = nil

        var changeSet = BlockLayoutChangeSet(
            updatedBlockIDs: dirtyInvalidation.blockIDs
        )
        guard
            applyVisibleOrderMutation(
                mutations: dirtyInvalidation.mutations,
                document: document,
                visibleIndex: nextVisibleIndex,
                changeSet: &changeSet
            )
        else {
            return nil
        }

        if !nextMarkerSequence.canReuseWithoutMarkerRefresh(after: changeSet, document: document),
            !nextMarkerSequence.applyIndependentStructuralMutation(
                document: document,
                visibleIndex: nextVisibleIndex,
                changeSet: changeSet
            )
        {
            nextMarkerSequence = BlockMarkerSequence(
                document: document,
                visibleIndex: nextVisibleIndex
            )
        }
        let contentSnapshot = EffectiveDocumentSnapshot(
            document: document,
            composition: composition
        )
        guard
            let revision = applyIncrementalLayout(
                contentSnapshot: contentSnapshot,
                visibleIndex: nextVisibleIndex,
                availableWidth: viewport.width,
                widthRevision: viewport.widthRevision,
                changeSet: changeSet,
                textLayouter: textLayouter
            )
        else {
            return nil
        }

        updateLayoutState(
            visibleIndex: nextVisibleIndex,
            markerSequence: nextMarkerSequence,
            widthRevision: viewport.widthRevision
        )
        return prepared(
            revision: revision,
            mode: .incremental,
            visibleOrderEntryCount:
                changeSet.insertedBlockIDs.count + changeSet.removedBlockIDs.count
                + changeSet.movedBlockIDs.count
        )
    }
}
