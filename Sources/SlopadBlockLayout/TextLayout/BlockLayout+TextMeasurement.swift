import SlopadCoreModel

// MARK: - Text Measurement

extension BlockLayout {
    mutating func measure(
        _ block: Block,
        visibleBlock: VisibleBlock,
        contentSnapshot: EffectiveDocumentSnapshot,
        availableWidth: Double,
        textLayouter: any BlockTextLayoutProtocol
    ) -> BlockMeasurement {
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            let result = cache.measurementWithCacheStatus(
                for: block,
                visibleBlock: visibleBlock,
                contentSnapshot: contentSnapshot,
                availableWidth: availableWidth,
                textLayoutRevision: textLayoutRevision,
                textLayouter: textLayouter
            )
            if result.usedCache {
                lastBenchmarkMetrics.cacheHitCount += 1
            } else {
                lastBenchmarkMetrics.cacheMissCount += 1
            }
            return result.measurement
        #else
            return cache.measurement(
                for: block,
                visibleBlock: visibleBlock,
                contentSnapshot: contentSnapshot,
                availableWidth: availableWidth,
                textLayoutRevision: textLayoutRevision,
                textLayouter: textLayouter
            )
        #endif
    }
}
