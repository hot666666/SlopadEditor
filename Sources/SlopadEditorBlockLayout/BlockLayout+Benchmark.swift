// MARK: - Block Layout Benchmark

#if SLOPAD_BENCHMARK_INSTRUMENTATION
extension BlockLayout {
    package var benchmarkMetrics: BlockLayoutBenchmarkMetrics {
        lastBenchmarkMetrics
    }
}
#endif
