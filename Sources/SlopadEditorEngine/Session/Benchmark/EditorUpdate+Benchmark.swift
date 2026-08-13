#if SLOPAD_BENCHMARK_INSTRUMENTATION

// MARK: - EditorUpdate Benchmark Metrics

extension EditorUpdate {
    package var benchmarkLayoutDirty: Bool {
        layoutDirty
    }

    package var benchmarkInvalidationBlockCount: Int {
        invalidation.blockIDs.count
    }

    package var benchmarkVisibleSequenceChanged: Bool {
        invalidation.visibleSequenceChanged
    }

    package var benchmarkLayoutGeometryChanged: Bool {
        invalidation.layoutGeometryChanged
    }
}

#endif
