import SlopadCoreModel

// MARK: - TextLayoutCache

struct TextLayoutCache {
    private struct MeasurementKey: Hashable {
        let blockID: BlockID
        let contentRevision: Int
        let compositionRevision: Int
        let availableWidth: Double
        let textLayoutRevision: Int
        let depth: Int
        let blockChromeSignature: String

        init(
            block: Block,
            visibleBlock: VisibleBlock,
            contentSnapshot: EffectiveDocumentSnapshot,
            availableWidth: Double,
            textLayoutRevision: Int
        ) {
            blockID = block.id
            contentRevision = block.content.revision
            compositionRevision =
                contentSnapshot.composition?.blockID == block.id
                ? contentSnapshot.compositionRevision
                : 0
            self.availableWidth = availableWidth
            self.textLayoutRevision = textLayoutRevision
            depth = visibleBlock.depth
            blockChromeSignature = block.kind.layoutChromeSignature
        }
    }

    private var measurements: [MeasurementKey: BlockMeasurement] = [:]

    mutating func measurement(
        for block: Block,
        visibleBlock: VisibleBlock,
        contentSnapshot: EffectiveDocumentSnapshot,
        availableWidth: Double,
        textLayoutRevision: Int,
        textLayouter: any BlockTextLayoutProtocol
    ) -> BlockMeasurement {
        measured(
            block,
            visibleBlock: visibleBlock,
            contentSnapshot: contentSnapshot,
            availableWidth: availableWidth,
            textLayoutRevision: textLayoutRevision,
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
            textLayouter: any BlockTextLayoutProtocol
        ) -> (measurement: BlockMeasurement, usedCache: Bool) {
            measured(
                block,
                visibleBlock: visibleBlock,
                contentSnapshot: contentSnapshot,
                availableWidth: availableWidth,
                textLayoutRevision: textLayoutRevision,
                textLayouter: textLayouter
            )
        }
    #endif

    private mutating func measured(
        _ block: Block,
        visibleBlock: VisibleBlock,
        contentSnapshot: EffectiveDocumentSnapshot,
        availableWidth: Double,
        textLayoutRevision: Int,
        textLayouter: any BlockTextLayoutProtocol
    ) -> (measurement: BlockMeasurement, usedCache: Bool) {
        let key = MeasurementKey(
            block: block,
            visibleBlock: visibleBlock,
            contentSnapshot: contentSnapshot,
            availableWidth: availableWidth,
            textLayoutRevision: textLayoutRevision
        )
        if let cached = measurements[key] {
            return (cached, true)
        }

        let measureRequest = BlockMeasureRequest(
            block: block,
            depth: visibleBlock.depth,
            availableWidth: availableWidth
        )
        let measurement = textLayouter.measure(measureRequest)
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

// MARK: - Block Chrome Signature

private extension BlockKind {
    var layoutChromeSignature: String {
        switch self {
        case .paragraph:
            "paragraph"

        case .heading(let level):
            "heading-\(level.rawValue)"

        case .unorderedListItem:
            "unorderedListItem"

        case .orderedListItem(let restartNumber):
            "orderedListItem-\(restartNumber.map(String.init) ?? "nil")"

        case .quote:
            "quote"

        case .codeBlock(let language):
            "codeBlock-\(language ?? "")"

        case .divider:
            "divider"

        case .todo(let isChecked):
            "todo-\(isChecked)"
        }
    }
}
