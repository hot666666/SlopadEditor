import SlopadCoreModel

struct RecordedTextNavigationRequest: Equatable {
    let selection: TextSelection
    let context: TextNavigationContext?
    let direction: TextNavigationDirection
    let destination: TextNavigationDestination
    let extending: Bool
    let measureRequest: BlockMeasureRequest
}

struct RecordedWordRangeRequest: Equatable {
    let position: TextPosition
    let measureRequest: BlockMeasureRequest
}

struct RecordedTextDeletionRequest: Equatable {
    let selection: TextSelection
    let direction: TextNavigationDirection
    let destination: TextNavigationDestination
    let measureRequest: BlockMeasureRequest
}

final class SpyBlockTextLayouter: BlockTextLayoutProtocol, @unchecked Sendable {
    var measurementsByBlockID: [BlockID: BlockMeasurement] = [:]
    var textFramesByBlockID: [BlockID: EditorRect] = [:]
    var lineFragmentsByBlockID: [BlockID: [LineFragmentSnapshot]] = [:]
    var caretRectsByPosition: [TextPosition: EditorRect] = [:]
    var textPositionsByBlockID: [BlockID: TextPosition] = [:]
    var textPositionResolver: ((BlockID, EditorPoint) -> TextPosition)?
    var textHitTestResolver: ((BlockID, EditorPoint) -> TextHitTestResult?)?
    var navigationResolver: ((RecordedTextNavigationRequest) -> TextNavigationResolution)?
    var wordRangeResolver: ((RecordedWordRangeRequest) -> TextRange?)?
    var deletionRangeResolver: ((RecordedTextDeletionRequest) -> TextRange?)?
    private(set) var textPositionRequests: [(blockID: BlockID, point: EditorPoint)] = []
    private(set) var navigationRequests: [RecordedTextNavigationRequest] = []
    private(set) var wordRangeRequests: [RecordedWordRangeRequest] = []
    private(set) var deletionRangeRequests: [RecordedTextDeletionRequest] = []

    private let navigationFallback = DeterministicBlockTextLayouter()

    func measure(_ request: BlockMeasureRequest) -> BlockMeasurement {
        measurementsByBlockID[request.blockID]
            ?? BlockMeasurement(height: textFramesByBlockID[request.blockID]?.height ?? 20)
    }

    func textFrame(for request: BlockMeasureRequest, measuredHeight: Double?) -> EditorRect {
        textFramesByBlockID[request.blockID]
            ?? EditorRect(
                x: 0,
                y: 0,
                width: request.availableWidth,
                height: measuredHeight ?? 1
            )
    }

    func lineFragments(for request: BlockMeasureRequest) -> [LineFragmentSnapshot] {
        lineFragmentsByBlockID[request.blockID]
            ?? [
                LineFragmentSnapshot(
                    blockID: request.blockID,
                    range: TextRange(0, request.text.count),
                    rect: EditorRect(x: 0, y: 0, width: request.availableWidth, height: 10)
                )
            ]
    }

    func caretRect(for position: TextPosition, in request: BlockMeasureRequest) -> EditorRect? {
        caretRectsByPosition[position]
    }

    func selectionRects(for range: TextRange, in request: BlockMeasureRequest) -> [EditorRect] {
        []
    }

    func textPosition(at point: EditorPoint, in request: BlockMeasureRequest) -> TextPosition {
        textPositionRequests.append((request.blockID, point))
        if let textPositionResolver {
            return textPositionResolver(request.blockID, point)
        }
        return textPositionsByBlockID[request.blockID]
            ?? TextPosition(blockID: request.blockID, offset: 0)
    }

    func textHitTest(
        at point: EditorPoint,
        in request: BlockMeasureRequest
    ) -> TextHitTestResult? {
        if let textHitTestResolver {
            textPositionRequests.append((request.blockID, point))
            return textHitTestResolver(request.blockID, point)
        }
        return TextHitTestResult(position: textPosition(at: point, in: request))
    }

    func navigate(
        selection: TextSelection,
        context: TextNavigationContext?,
        direction: TextNavigationDirection,
        destination: TextNavigationDestination,
        extending: Bool,
        in request: BlockMeasureRequest
    ) -> TextNavigationResolution {
        let recorded = RecordedTextNavigationRequest(
            selection: selection,
            context: context,
            direction: direction,
            destination: destination,
            extending: extending,
            measureRequest: request
        )
        navigationRequests.append(recorded)
        return navigationResolver?(recorded)
            ?? navigationFallback.navigate(
                selection: selection,
                context: context,
                direction: direction,
                destination: destination,
                extending: extending,
                in: request
            )
    }

    func wordRange(
        containing position: TextPosition,
        in request: BlockMeasureRequest
    ) -> TextRange? {
        let recorded = RecordedWordRangeRequest(position: position, measureRequest: request)
        wordRangeRequests.append(recorded)
        if let wordRangeResolver {
            return wordRangeResolver(recorded)
        }
        return navigationFallback.wordRange(containing: position, in: request)
    }

    func deletionRange(
        for selection: TextSelection,
        direction: TextNavigationDirection,
        destination: TextNavigationDestination,
        in request: BlockMeasureRequest
    ) -> TextRange? {
        let recorded = RecordedTextDeletionRequest(
            selection: selection,
            direction: direction,
            destination: destination,
            measureRequest: request
        )
        deletionRangeRequests.append(recorded)
        if let deletionRangeResolver {
            return deletionRangeResolver(recorded)
        }
        return navigationFallback.deletionRange(
            for: selection,
            direction: direction,
            destination: destination,
            in: request
        )
    }
}
