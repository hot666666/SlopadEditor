import SlopadBlockLayout
import SlopadCoreModel

// MARK: - EditorSession LayoutPreparation

extension EditorSession {
    func preparedLayout(
        for viewport: EditorViewport
    ) -> EditorSnapshotRevision {
        let revision = blockLayout.prepare(
            document: editorModel.document,
            composition: composition,
            viewport: viewport,
            textLayouter: blockMeasuring
        )

        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            let layoutMetrics = blockLayout.benchmarkMetrics
            benchmarkMetrics.layoutMode = layoutMetrics.layoutMode?.rawValue ?? "none"
            benchmarkMetrics.visibleOrderEntryCount = layoutMetrics.visibleOrderEntryCount
            benchmarkMetrics.layoutInputBlockCount = layoutMetrics.inputBlockCount
            benchmarkMetrics.layoutOutputBlockCount = layoutMetrics.outputBlockCount
            benchmarkMetrics.cacheHitCount = layoutMetrics.cacheHitCount
            benchmarkMetrics.cacheMissCount = layoutMetrics.cacheMissCount
            benchmarkMetrics.heightIndexRebuildCount =
                layoutMetrics.heightIndexRebuildCount
            benchmarkMetrics.heightIndexInsertCount = layoutMetrics.heightIndexInsertCount
            benchmarkMetrics.heightIndexRemoveCount = layoutMetrics.heightIndexRemoveCount
            benchmarkMetrics.heightIndexMoveCount = layoutMetrics.heightIndexMoveCount
            benchmarkMetrics.heightIndexUpdateHeightCount =
                layoutMetrics.heightIndexUpdateHeightCount
        #endif

        return revision
    }
}
