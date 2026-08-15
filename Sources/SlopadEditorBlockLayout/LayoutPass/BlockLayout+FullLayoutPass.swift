import SlopadEditorCoreModel

// MARK: - Full Layout Pass

extension BlockLayout {
    mutating func layout(
        contentSnapshot: EffectiveDocumentSnapshot,
        visibleIndex: VisibleBlockIndex,
        viewport: EditorViewport,
        textLayouter: any BlockMeasuring
    ) -> EditorSnapshotRevision {
        guard shouldUseLazyLayout(visibleIndex: visibleIndex) else {
            return layout(
                contentSnapshot: contentSnapshot,
                visibleIndex: visibleIndex,
                availableWidth: viewport.width,
                widthRevision: viewport.widthRevision,
                textLayouter: textLayouter
            )
        }
        return layoutLazy(
            contentSnapshot: contentSnapshot,
            visibleIndex: visibleIndex,
            viewport: viewport,
            textLayouter: textLayouter
        )
    }

    mutating func layout(
        contentSnapshot: EffectiveDocumentSnapshot,
        visibleIndex: VisibleBlockIndex,
        availableWidth: Double,
        widthRevision: Int?,
        textLayouter: any BlockMeasuring
    ) -> EditorSnapshotRevision {
        var measurements: [BlockID: BlockMeasurement] = [:]
        var heightEntries: [BlockHeightIndexStorage.Entry] = []
        let visibleEntries = visibleIndex.entriesSnapshot()
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            lastBenchmarkMetrics = BlockLayoutBenchmarkMetrics()
            lastBenchmarkMetrics.inputBlockCount = visibleEntries.count
            lastBenchmarkMetrics.heightIndexRebuildCount = 1
        #endif
        let layoutRevision = makeRevision(
            contentSnapshot: contentSnapshot,
            visibleIndex: visibleIndex,
            availableWidth: availableWidth,
            widthRevision: widthRevision
        )

        for visible in visibleEntries {
            guard let block = contentSnapshot.block(for: visible.blockID) else { continue }

            let measurement = measure(
                block,
                visibleBlock: visible,
                contentSnapshot: contentSnapshot,
                availableWidth: availableWidth,
                textLayouter: textLayouter
            )
            measurements[block.id] = measurement

            heightEntries.append(
                BlockHeightIndexStorage.Entry(blockID: block.id, height: measurement.height))
            #if SLOPAD_BENCHMARK_INSTRUMENTATION
                lastBenchmarkMetrics.heightIndexInsertCount += 1
            #endif
        }

        heightIndex = BlockHeightIndexStorage(entries: heightEntries)
        measurementsByBlockID = measurements
        currentRevision = layoutRevision
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            lastBenchmarkMetrics.outputBlockCount = heightEntries.count
        #endif

        return layoutRevision
    }
}

// MARK: - Lazy Full Layout Pass

extension BlockLayout {
    private func shouldUseLazyLayout(visibleIndex: VisibleBlockIndex) -> Bool {
        visibleIndex.count >= blockLayoutLazyMeasurementMinimumBlockCount
    }

    private mutating func layoutLazy(
        contentSnapshot: EffectiveDocumentSnapshot,
        visibleIndex: VisibleBlockIndex,
        viewport: EditorViewport,
        textLayouter: any BlockMeasuring
    ) -> EditorSnapshotRevision {
        let visibleEntries = visibleIndex.entriesSnapshot()
        let previousMeasurementsByBlockID = measurementsByBlockID
        var heightEntries: [BlockHeightIndexStorage.Entry] = []
        heightEntries.reserveCapacity(visibleEntries.count)

        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            lastBenchmarkMetrics = BlockLayoutBenchmarkMetrics()
            lastBenchmarkMetrics.heightIndexRebuildCount = 1
            lastBenchmarkMetrics.heightIndexInsertCount = visibleEntries.count
        #endif

        let layoutRevision = makeRevision(
            contentSnapshot: contentSnapshot,
            visibleIndex: visibleIndex,
            availableWidth: viewport.width,
            widthRevision: viewport.widthRevision
        )

        for visible in visibleEntries {
            guard let block = contentSnapshot.block(for: visible.blockID) else { continue }
            let estimatedMeasurement =
                previousMeasurementsByBlockID[block.id]
                ?? estimatedLazyMeasurement(for: block)
            heightEntries.append(
                BlockHeightIndexStorage.Entry(
                    blockID: block.id, height: estimatedMeasurement.height)
            )
        }

        heightIndex = BlockHeightIndexStorage(entries: heightEntries)
        measurementsByBlockID = [:]
        currentRevision = layoutRevision

        let measuredCount = measureViewportIfNeeded(
            contentSnapshot: contentSnapshot,
            visibleIndex: visibleIndex,
            viewport: viewport,
            textLayouter: textLayouter
        )

        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            lastBenchmarkMetrics.inputBlockCount = measuredCount
            lastBenchmarkMetrics.outputBlockCount = heightEntries.count
        #endif

        return layoutRevision
    }
}

// MARK: - Lazy Measurement

extension BlockLayout {
    @discardableResult
    mutating func measureBlockIfNeeded(
        blockID: BlockID,
        contentSnapshot: EffectiveDocumentSnapshot,
        availableWidth: Double,
        textLayouter: any BlockMeasuring
    ) -> Bool {
        guard let visibleBlock = visibleIndex?.entry(for: blockID) else { return false }
        return measureBlockIfNeeded(
            visibleBlock: visibleBlock,
            contentSnapshot: contentSnapshot,
            availableWidth: availableWidth,
            textLayouter: textLayouter
        )
    }

    @discardableResult
    mutating func measureViewportIfNeeded(
        contentSnapshot: EffectiveDocumentSnapshot,
        visibleIndex: VisibleBlockIndex,
        viewport: EditorViewport,
        textLayouter: any BlockMeasuring
    ) -> Int {
        var measuredCount = 0
        for _ in 0..<blockLayoutLazyMeasurementMaxViewportPasses {
            let beforePassCount = measuredCount
            let range = viewportMeasurementRange(
                yOffset: viewport.scrollY,
                viewportHeight: viewport.height,
                visibleCount: visibleIndex.count
            )
            guard !range.isEmpty else { break }

            for visible in visibleIndex.entries(in: range) {
                if measurementsByBlockID[visible.blockID] != nil { continue }
                if measureBlockIfNeeded(
                    visibleBlock: visible,
                    contentSnapshot: contentSnapshot,
                    availableWidth: viewport.width,
                    textLayouter: textLayouter
                ) {
                    measuredCount += 1
                }
            }

            guard measuredCount != beforePassCount else { break }
        }
        return measuredCount
    }

    private mutating func measureBlockIfNeeded(
        visibleBlock: VisibleBlock,
        contentSnapshot: EffectiveDocumentSnapshot,
        availableWidth: Double,
        textLayouter: any BlockMeasuring
    ) -> Bool {
        guard measurementsByBlockID[visibleBlock.blockID] == nil,
            heightIndex.index(of: visibleBlock.blockID) != nil,
            let block = contentSnapshot.block(for: visibleBlock.blockID)
        else {
            return false
        }

        let measurement = measure(
            block,
            visibleBlock: visibleBlock,
            contentSnapshot: contentSnapshot,
            availableWidth: availableWidth,
            textLayouter: textLayouter
        )
        measurementsByBlockID[block.id] = measurement
        heightIndex.updateHeight(blockID: block.id, height: measurement.height)
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            lastBenchmarkMetrics.heightIndexUpdateHeightCount += 1
        #endif
        return true
    }

    private func viewportMeasurementRange(
        yOffset: Double,
        viewportHeight: Double,
        visibleCount: Int
    ) -> Range<Int> {
        let visibleRange = heightIndex.visibleRange(
            yOffset: yOffset,
            viewportHeight: viewportHeight
        )
        guard !visibleRange.isEmpty else { return 0..<0 }
        let lowerBound = max(
            0,
            visibleRange.lowerBound - blockLayoutLazyMeasurementPrefetchBlockMargin
        )
        let upperBound = min(
            visibleCount,
            visibleRange.upperBound + blockLayoutLazyMeasurementPrefetchBlockMargin
        )
        return lowerBound..<upperBound
    }
}

private let blockLayoutLazyMeasurementMinimumBlockCount = 512
private let blockLayoutLazyMeasurementPrefetchBlockMargin = 8
private let blockLayoutLazyMeasurementMaxViewportPasses = 64

private func estimatedLazyMeasurement(for block: Block) -> BlockMeasurement {
    let baseHeight: Double
    switch block.kind {
    case .heading(let level):
        switch level {
        case .h1:
            baseHeight = 52
        case .h2:
            baseHeight = 46
        case .h3:
            baseHeight = 40
        }
    case .divider:
        baseHeight = 18
    case .codeBlock:
        baseHeight = 40
    case .custom:
        // A placeholder for the lazy pass only. The real height comes from the host's
        // sizing function through the ordinary measurement path, which this estimate
        // exists to stand in for until that block is measured.
        baseHeight = 36
    case .paragraph, .unorderedListItem, .orderedListItem, .quote, .todo:
        baseHeight = 36
    }
    return BlockMeasurement(height: baseHeight)
}
