import SlopadEditorCoreModel

// MARK: - TextLayoutCache

/// Caches block measurements, keyed on the request that produced them.
///
/// The key *is* `BlockMeasureRequest`. That request is the complete input to measurement —
/// text, kind, inline runs, width, depth — so equal keys mean equal measurements by
/// construction, and there is no rule anyone has to remember to follow.
///
/// The previous key indexed on revisions instead: `content.revision` for the text,
/// `compositionRevision` for composition, and a `blockChromeSignature` string re-encoding
/// `BlockKind`. That works only while every mutation remembers to bump a counter. It already
/// returned a stale height for two different documents that shared a block ID and revision —
/// unreachable in production, because document replacement rebuilds `BlockLayout`, but the
/// fragility was real and is now gone.
///
/// `textLayoutRevision` is not part of the key either: replacing the backend calls
/// `advanceTextLayoutRevision`, which clears this cache outright, so a stale entry from a
/// previous backend cannot survive to be looked up.
struct TextLayoutCache {
    /// The same value axis as `BlockMeasureRequest`, minus the derived part.
    ///
    /// `BlockMeasureRequest.inlineRuns` is computed from `text` and `marks` — it allocates a
    /// substring per run — so keying on the request itself paid that cost on every cache
    /// probe, including hits. Measured at 5-8% on scroll and structural-edit scenarios.
    /// Keying on the inputs instead defers it to a miss, where the measurement is about to be
    /// taken anyway, without weakening the key: equal text and marks produce equal runs.
    private struct MeasurementKey: Hashable {
        let blockID: BlockID
        let text: String
        let kind: BlockKind
        let marks: [BlockContent.InlineMark]
        let availableWidth: Double
        let depth: Int

        init(block: Block, depth: Int, availableWidth: Double) {
            blockID = block.id
            text = block.content.text
            kind = block.kind
            marks = block.content.marks
            self.availableWidth = availableWidth
            self.depth = depth
        }
    }

    private var measurements: [MeasurementKey: BlockMeasurement] = [:]

    mutating func measurement(
        for block: Block,
        visibleBlock: VisibleBlock,
        contentSnapshot: EffectiveDocumentSnapshot,
        availableWidth: Double,
        textLayoutRevision: Int,
        textLayouter: any BlockMeasuring
    ) -> BlockMeasurement {
        measured(
            block,
            visibleBlock: visibleBlock,
            availableWidth: availableWidth,
            textLayouter: textLayouter
        ).measurement
    }

    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        mutating func measurementWithCacheStatus(
            for block: Block,
            visibleBlock: VisibleBlock,
            contentSnapshot: EffectiveDocumentSnapshot,
            availableWidth: Double,
            textLayoutRevision: Int,
            textLayouter: any BlockMeasuring
        ) -> (measurement: BlockMeasurement, usedCache: Bool) {
            measured(
                block,
                visibleBlock: visibleBlock,
                availableWidth: availableWidth,
                textLayouter: textLayouter
            )
        }
    #endif

    private mutating func measured(
        _ block: Block,
        visibleBlock: VisibleBlock,
        availableWidth: Double,
        textLayouter: any BlockMeasuring
    ) -> (measurement: BlockMeasurement, usedCache: Bool) {
        let key = MeasurementKey(
            block: block, depth: visibleBlock.depth, availableWidth: availableWidth)
        if let cached = measurements[key] {
            return (cached, true)
        }

        let measurement = textLayouter.measure(
            BlockMeasureRequest(
                block: block,
                depth: visibleBlock.depth,
                availableWidth: availableWidth
            ))
        measurements[key] = measurement
        return (measurement, false)
    }

    mutating func invalidate(blockID: BlockID) {
        measurements = measurements.filter { $0.key.blockID != blockID }
    }

    mutating func invalidateAll() {
        measurements.removeAll()
    }
}
