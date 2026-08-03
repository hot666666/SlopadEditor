import SlopadEditorModel

// MARK: - EditorSession Benchmark

#if SLOPAD_BENCHMARK_INSTRUMENTATION
extension EditorSession {
    package func resetBenchmarkMetrics() {
        benchmarkMetrics = EditorSessionBenchmarkMetrics()
    }

    package var lastBenchmarkMetrics: EditorSessionBenchmarkMetrics {
        benchmarkMetrics
    }

    package var documentBlockCount: Int {
        editorModel.document.blocks.count
    }

}

// MARK: - EditorSessionBenchmarkMetrics

package struct EditorSessionBenchmarkMetrics {
    package var layoutMode: String = "none"
    package var visibleOrderEntryCount: Int = 0
    package var layoutInputBlockCount: Int = 0
    package var layoutOutputBlockCount: Int = 0
    package var cacheHitCount: Int = 0
    package var cacheMissCount: Int = 0
    package var heightIndexRebuildCount: Int = 0
    package var heightIndexInsertCount: Int = 0
    package var heightIndexRemoveCount: Int = 0
    package var heightIndexMoveCount: Int = 0
    package var heightIndexUpdateHeightCount: Int = 0
}
#endif
