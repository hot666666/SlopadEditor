// MARK: - BlockLayoutInstrumentation

#if SLOPAD_BENCHMARK_INSTRUMENTATION
package enum BlockLayoutMode: String {
    case reusedSnapshot
    case fullRebuild
    case incremental
}
#else
enum BlockLayoutMode: String {
    case reusedSnapshot
    case fullRebuild
    case incremental
}
#endif

#if SLOPAD_BENCHMARK_INSTRUMENTATION
package struct BlockLayoutBenchmarkMetrics {
    package var layoutMode: BlockLayoutMode?
    package var visibleOrderEntryCount: Int = 0
    package var inputBlockCount: Int = 0
    package var outputBlockCount: Int = 0
    package var cacheHitCount: Int = 0
    package var cacheMissCount: Int = 0
    package var heightIndexRebuildCount: Int = 0
    package var heightIndexInsertCount: Int = 0
    package var heightIndexRemoveCount: Int = 0
    package var heightIndexMoveCount: Int = 0
    package var heightIndexUpdateHeightCount: Int = 0
}
#endif
