import SlopadEditorCoreModel

// MARK: - Block Layout Preparation

extension BlockLayout {
    package mutating func prepare(
        document: Document,
        composition: TextComposition?,
        viewport: EditorViewport,
        textLayouter: any BlockMeasuring
    ) -> EditorSnapshotRevision {
        let widthRevision = viewport.widthRevision
        if !needsLayout(widthRevision: widthRevision),
            let visibleIndex,
            markerSequence != nil,
            let revision = currentRevision
        {
            let contentSnapshot = EffectiveDocumentSnapshot(
                document: document,
                composition: composition
            )
            #if SLOPAD_BENCHMARK_INSTRUMENTATION
                lastBenchmarkMetrics = BlockLayoutBenchmarkMetrics()
            #endif
            let measuredCount = measureViewportIfNeeded(
                contentSnapshot: contentSnapshot,
                visibleIndex: visibleIndex,
                viewport: viewport,
                textLayouter: textLayouter
            )
            if measuredCount > 0 {
                #if SLOPAD_BENCHMARK_INSTRUMENTATION
                    lastBenchmarkMetrics.inputBlockCount = measuredCount
                    lastBenchmarkMetrics.outputBlockCount = measuredCount
                #endif
                return prepared(
                    revision: revision,
                    mode: .incremental,
                    visibleOrderEntryCount: 0
                )
            }
            return prepared(
                revision: revision,
                mode: .reusedSnapshot,
                visibleOrderEntryCount: 0
            )
        }

        if canRelayoutDirtyBlocks(widthRevision: widthRevision),
            let visibleIndex,
            let markerSequence
        {
            var nextMarkerSequence = markerSequence
            if needsMarkerStateUpdate(mutations: dirtyInvalidation.mutations),
                !nextMarkerSequence.refreshIndependentMarkers(
                    blockIDs: dirtyInvalidation.blockIDs,
                    document: document,
                    visibleIndex: visibleIndex
                )
            {
                nextMarkerSequence = BlockMarkerSequence(
                    document: document,
                    visibleIndex: visibleIndex
                )
            }
            let contentSnapshot = EffectiveDocumentSnapshot(
                document: document,
                composition: composition
            )
            if let revision = applyIncrementalLayout(
                contentSnapshot: contentSnapshot,
                visibleIndex: visibleIndex,
                availableWidth: viewport.width,
                widthRevision: widthRevision,
                changeSet: BlockLayoutChangeSet(updatedBlockIDs: dirtyInvalidation.blockIDs),
                textLayouter: textLayouter
            ) {
                updateLayoutState(
                    visibleIndex: visibleIndex,
                    markerSequence: nextMarkerSequence,
                    widthRevision: widthRevision
                )
                return prepared(
                    revision: revision,
                    mode: .incremental,
                    visibleOrderEntryCount: 0
                )
            }
        }

        if canApplyStructuralOperations(widthRevision: widthRevision),
            let prepared = applyStructuralOperations(
                document: document,
                composition: composition,
                viewport: viewport,
                textLayouter: textLayouter
            )
        {
            return prepared
        }

        let visibleIndex = VisibleBlockIndex(document: document)
        let markerSequence = BlockMarkerSequence(
            document: document,
            visibleIndex: visibleIndex
        )
        let contentSnapshot = EffectiveDocumentSnapshot(
            document: document,
            composition: composition
        )
        let revision = layout(
            contentSnapshot: contentSnapshot,
            visibleIndex: visibleIndex,
            viewport: viewport,
            textLayouter: textLayouter
        )
        updateLayoutState(
            visibleIndex: visibleIndex,
            markerSequence: markerSequence,
            widthRevision: widthRevision
        )
        return prepared(
            revision: revision,
            mode: .fullRebuild,
            visibleOrderEntryCount: visibleIndex.count
        )
    }

    private func hasPreparedLayout(widthRevision: Int) -> Bool {
        currentRevision != nil
            && visibleIndex != nil
            && markerSequence != nil
            && self.widthRevision == widthRevision
    }

    private func needsLayout(widthRevision: Int) -> Bool {
        !hasPreparedLayout(widthRevision: widthRevision) || isDirty
    }

    private func canRelayoutDirtyBlocks(widthRevision: Int) -> Bool {
        hasPreparedLayout(widthRevision: widthRevision)
            && !dirtyInvalidation.blockIDs.isEmpty
            && !dirtyInvalidation.visibleSequenceChanged
    }

    private func canApplyStructuralOperations(widthRevision: Int) -> Bool {
        hasPreparedLayout(widthRevision: widthRevision)
            && dirtyInvalidation.visibleSequenceChanged
            && !dirtyInvalidation.mutations.isEmpty
    }

    private func needsMarkerStateUpdate(mutations: [BlockLayoutMutation]) -> Bool {
        mutations.contains { mutation in
            if case .refreshMarker = mutation { return true }
            return false
        }
    }
}
