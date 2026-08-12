import SlopadEditorCoreModel

// Stays on the composed protocol: `EditorSession.init` takes the whole seam, because a
// backend adopts all four capabilities. Only doubles that never reach Session can be
// narrowed. What did narrow is the BlockLayout-side test helpers, which now ask for
// `any BlockMeasuring` — so a double that only measures is now accepted there.
final class RecordingBlockTextLayouter: BlockTextLayoutProtocol, @unchecked Sendable {
    var measuredBlockIDs: [BlockID] = []
    private let measurementsByBlockID: [BlockID: BlockMeasurement]
    private let fallbackBaseHeight: Double

    init(
        measurementsByBlockID: [BlockID: BlockMeasurement] = [:],
        fallbackBaseHeight: Double = 10
    ) {
        self.measurementsByBlockID = measurementsByBlockID
        self.fallbackBaseHeight = fallbackBaseHeight
    }

    func measure(_ request: BlockMeasureRequest) -> BlockMeasurement {
        measuredBlockIDs.append(request.blockID)
        if let measurement = measurementsByBlockID[request.blockID] {
            return measurement
        }
        return BlockMeasurement(height: fallbackBaseHeight + Double(request.text.count))
    }

    func textFrame(for request: BlockMeasureRequest, measuredHeight: Double?) -> EditorRect {
        EditorRect(x: 0, y: 0, width: request.availableWidth, height: measuredHeight ?? 1)
    }

    func lineFragments(for request: BlockMeasureRequest) -> [LineFragmentSnapshot] {
        [
            LineFragmentSnapshot(
                blockID: request.blockID,
                range: TextRange(0, request.text.count),
                rect: EditorRect(x: 0, y: 0, width: request.availableWidth, height: 10)
            )
        ]
    }

    func caretRect(for position: TextPosition, in request: BlockMeasureRequest) -> EditorRect? {
        guard position.blockID == request.blockID else { return nil }
        return EditorRect(x: Double(position.offset), y: 0, width: 1, height: 10)
    }

    func selectionRects(for range: TextRange, in request: BlockMeasureRequest) -> [EditorRect] {
        guard !range.isEmpty else { return [] }
        return [
            EditorRect(
                x: Double(range.lowerBound),
                y: 0,
                width: Double(range.length),
                height: 10
            )
        ]
    }

    func textPosition(at point: EditorPoint, in request: BlockMeasureRequest) -> TextPosition {
        TextPosition(
            blockID: request.blockID,
            offset: max(0, min(request.text.count, Int(point.x.rounded())))
        )
    }
}
