import SlopadCoreModel

// MARK: - BlockLayout

package struct BlockLayout {
    var widthRevision: Int?
    var textLayoutRevision: Int
    var dirtyInvalidation: BlockLayoutInvalidation
    var currentRevision: EditorSnapshotRevision?
    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        var lastBenchmarkMetrics: BlockLayoutBenchmarkMetrics
    #endif
    var cache: TextLayoutCache
    var visibleIndex: VisibleBlockIndex?
    var markerSequence: BlockMarkerSequence?
    var measurementsByBlockID: [BlockID: BlockMeasurement]
    var heightIndex: BlockHeightIndexStorage

    package init() {
        self.init(cache: TextLayoutCache())
    }

    private init(cache: TextLayoutCache) {
        self.cache = cache
        self.heightIndex = BlockHeightIndexStorage()
        self.textLayoutRevision = 0
        self.visibleIndex = nil
        self.markerSequence = nil
        self.widthRevision = nil
        self.dirtyInvalidation = BlockLayoutInvalidation()
        self.currentRevision = nil
        self.measurementsByBlockID = [:]
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            self.lastBenchmarkMetrics = BlockLayoutBenchmarkMetrics()
        #endif
    }

    mutating func updateLayoutState(
        visibleIndex: VisibleBlockIndex,
        markerSequence: BlockMarkerSequence,
        widthRevision: Int
    ) {
        self.visibleIndex = visibleIndex
        self.markerSequence = markerSequence
        self.widthRevision = widthRevision
        self.dirtyInvalidation = BlockLayoutInvalidation()
    }

    func currentVisibleIndex(document: Document) -> VisibleBlockIndex {
        visibleIndex ?? VisibleBlockIndex(document: document)
    }
}
