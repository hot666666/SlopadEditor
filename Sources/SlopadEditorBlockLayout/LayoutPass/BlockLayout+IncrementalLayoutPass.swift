import SlopadCoreModel

// MARK: - Incremental Layout Pass

extension BlockLayout {
    mutating func applyIncrementalLayout(
        contentSnapshot: EffectiveDocumentSnapshot,
        visibleIndex: VisibleBlockIndex,
        availableWidth: Double,
        widthRevision: Int?,
        changeSet: BlockLayoutChangeSet,
        textLayouter: any BlockMeasuring
    ) -> EditorSnapshotRevision? {
        guard currentRevision != nil else { return nil }

        let layoutRevision = makeRevision(
            contentSnapshot: contentSnapshot,
            visibleIndex: visibleIndex,
            availableWidth: availableWidth,
            widthRevision: widthRevision
        )
        let inserted = Set(changeSet.insertedBlockIDs)
        let removed = Set(changeSet.removedBlockIDs)
        let moved = Set(changeSet.movedBlockIDs).subtracting(inserted).subtracting(removed)
        var updatedBlockIDs = changeSet.updatedBlockIDs
        updatedBlockIDs.subtract(inserted)
        updatedBlockIDs.subtract(removed)
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            lastBenchmarkMetrics = BlockLayoutBenchmarkMetrics()
            lastBenchmarkMetrics.inputBlockCount = inserted.count + updatedBlockIDs.count
        #endif

        for blockID in changeSet.removedBlockIDs {
            if heightIndex.remove(blockID: blockID) != nil {
                measurementsByBlockID.removeValue(forKey: blockID)
                #if SLOPAD_BENCHMARK_INSTRUMENTATION
                    lastBenchmarkMetrics.heightIndexRemoveCount += 1
                #endif
            }
        }

        var movedEntries: [BlockID: BlockHeightIndexStorage.Entry] = [:]
        for blockID in changeSet.movedBlockIDs where moved.contains(blockID) {
            if let entry = heightIndex.remove(blockID: blockID) {
                movedEntries[blockID] = entry
            }
        }

        let pendingBlockIDs = Array(movedEntries.keys) + changeSet.insertedBlockIDs
        let orderedPendingBlockIDs = pendingBlockIDs.sorted {
            (visibleIndex.index(of: $0) ?? Int.max)
                < (visibleIndex.index(of: $1) ?? Int.max)
        }
        var outputCount = 0
        for blockID in orderedPendingBlockIDs {
            guard let index = visibleIndex.index(of: blockID) else { continue }

            if let entry = movedEntries[blockID] {
                heightIndex.insert(entry, at: index)
                #if SLOPAD_BENCHMARK_INSTRUMENTATION
                    lastBenchmarkMetrics.heightIndexMoveCount += 1
                #endif
                continue
            }

            guard
                let visibleBlock = visibleIndex.entry(for: blockID),
                let block = contentSnapshot.block(for: blockID)
            else {
                continue
            }

            let measurement = measure(
                block,
                visibleBlock: visibleBlock,
                contentSnapshot: contentSnapshot,
                availableWidth: availableWidth,
                textLayouter: textLayouter
            )
            measurementsByBlockID[blockID] = measurement
            heightIndex.insert(
                BlockHeightIndexStorage.Entry(blockID: blockID, height: measurement.height),
                at: index
            )
            outputCount += 1
            #if SLOPAD_BENCHMARK_INSTRUMENTATION
                lastBenchmarkMetrics.heightIndexInsertCount += 1
            #endif
        }

        let orderedBlockIDs = updatedBlockIDs.sorted {
            (visibleIndex.index(of: $0) ?? Int.max)
                < (visibleIndex.index(of: $1) ?? Int.max)
        }
        for blockID in orderedBlockIDs {
            guard
                heightIndex.index(of: blockID) != nil,
                let visibleBlock = visibleIndex.entry(for: blockID),
                let block = contentSnapshot.block(for: blockID)
            else {
                continue
            }

            let measurement = measure(
                block,
                visibleBlock: visibleBlock,
                contentSnapshot: contentSnapshot,
                availableWidth: availableWidth,
                textLayouter: textLayouter
            )
            measurementsByBlockID[blockID] = measurement
            heightIndex.updateHeight(blockID: blockID, height: measurement.height)
            outputCount += 1
            #if SLOPAD_BENCHMARK_INSTRUMENTATION
                lastBenchmarkMetrics.heightIndexUpdateHeightCount += 1
            #endif
        }

        currentRevision = layoutRevision
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            lastBenchmarkMetrics.outputBlockCount = outputCount
        #endif
        return layoutRevision
    }
}
