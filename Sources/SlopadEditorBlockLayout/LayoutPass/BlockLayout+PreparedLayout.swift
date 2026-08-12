import SlopadCoreModel

// MARK: - Prepared Layout

extension BlockLayout {
    mutating func prepared(
        revision: EditorSnapshotRevision,
        mode: BlockLayoutMode,
        visibleOrderEntryCount: Int
    ) -> EditorSnapshotRevision {
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            switch mode {
            case .reusedSnapshot:
                lastBenchmarkMetrics = BlockLayoutBenchmarkMetrics()
            case .fullRebuild, .incremental:
                break
            }
            lastBenchmarkMetrics.layoutMode = mode
            lastBenchmarkMetrics.visibleOrderEntryCount = visibleOrderEntryCount
        #endif
        return revision
    }
}
