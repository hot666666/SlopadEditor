import SlopadCoreModel

struct DeterministicBlockTextLayouter: BlockTextLayoutProtocol, Sendable {
    var lineHeight: Double
    var verticalPadding: Double
    var horizontalInset: Double
    var verticalInset: Double
    var characterWidth: Double

    init(
        lineHeight: Double = 20,
        verticalPadding: Double = 8,
        horizontalInset: Double = 0,
        verticalInset: Double = 0,
        characterWidth: Double = 8
    ) {
        self.lineHeight = lineHeight
        self.verticalPadding = verticalPadding
        self.horizontalInset = horizontalInset
        self.verticalInset = verticalInset
        self.characterWidth = characterWidth
    }

    func measure(_ request: BlockMeasureRequest) -> BlockMeasurement {
        let lineCount = max(
            1,
            request.text.split(separator: "\n", omittingEmptySubsequences: false).count
        )
        let kindMultiplier: Double
        switch request.kind {
        case .heading(let level):
            kindMultiplier = level == .h1 ? 1.5 : (level == .h2 ? 1.3 : 1.15)
        case .divider:
            kindMultiplier = 0.5
        case .codeBlock:
            kindMultiplier = 1.1
        default:
            kindMultiplier = 1.0
        }
        return BlockMeasurement(
            height: Double(lineCount) * lineHeight * kindMultiplier + verticalPadding
        )
    }

    func textFrame(for request: BlockMeasureRequest, measuredHeight: Double?) -> EditorRect {
        EditorRect(
            x: horizontalInset,
            y: verticalInset,
            width: max(1, request.availableWidth - horizontalInset * 2),
            height: max(1, (measuredHeight ?? lineHeight) - verticalInset)
        )
    }

    func lineFragments(for request: BlockMeasureRequest) -> [LineFragmentSnapshot] {
        let lines = request.text.split(separator: "\n", omittingEmptySubsequences: false)
        var fragments: [LineFragmentSnapshot] = []
        fragments.reserveCapacity(max(1, lines.count))
        var lower = 0
        for (index, line) in lines.enumerated() {
            let upper = lower + line.count
            let width = max(1, Double(max(1, line.count)) * characterWidth)
            fragments.append(
                LineFragmentSnapshot(
                    blockID: request.blockID,
                    range: TextRange(lower, upper),
                    rect: EditorRect(
                        x: horizontalInset,
                        y: verticalInset + Double(index) * lineHeight,
                        width: width,
                        height: lineHeight
                    )
                )
            )
            lower = upper + 1
        }
        if fragments.isEmpty {
            fragments.append(
                LineFragmentSnapshot(
                    blockID: request.blockID,
                    range: .point(0),
                    rect: EditorRect(
                        x: horizontalInset,
                        y: verticalInset,
                        width: characterWidth,
                        height: lineHeight
                    )
                )
            )
        }
        return fragments
    }

    func caretRect(for position: TextPosition, in request: BlockMeasureRequest) -> EditorRect? {
        guard position.blockID == request.blockID else { return nil }
        let offset = TextRange.point(position.offset).clamped(to: request.text.count).lowerBound
        let fragments = lineFragments(for: request)
        let fragment =
            fragments.last {
                $0.range.lowerBound <= offset && offset <= $0.range.upperBound
            } ?? fragments.last
        guard let fragment else { return nil }
        let localOffset = max(0, offset - fragment.range.lowerBound)
        return EditorRect(
            x: fragment.rect.x + Double(localOffset) * characterWidth,
            y: fragment.rect.y,
            width: 1,
            height: fragment.rect.height
        )
    }

    func selectionRects(for range: TextRange, in request: BlockMeasureRequest) -> [EditorRect] {
        let clamped = range.clamped(to: request.text.count)
        guard !clamped.isEmpty else { return [] }
        return lineFragments(for: request).compactMap { fragment in
            guard fragment.range.intersects(clamped) else { return nil }
            let lower = max(clamped.lowerBound, fragment.range.lowerBound)
            let upper = min(clamped.upperBound, fragment.range.upperBound)
            return EditorRect(
                x: fragment.rect.x + Double(lower - fragment.range.lowerBound) * characterWidth,
                y: fragment.rect.y,
                width: max(1, Double(upper - lower) * characterWidth),
                height: fragment.rect.height
            )
        }
    }

    func textPosition(at point: EditorPoint, in request: BlockMeasureRequest) -> TextPosition {
        let fragments = lineFragments(for: request)
        let nearest =
            fragments.min { lhs, rhs in
                abs(lhs.rect.midY - point.y) < abs(rhs.rect.midY - point.y)
            } ?? fragments[0]
        let localX = max(0, point.x - nearest.rect.x)
        let offset = nearest.range.lowerBound + Int((localX / max(1, characterWidth)).rounded())
        return TextPosition(
            blockID: request.blockID,
            offset: min(request.text.count, max(nearest.range.lowerBound, offset))
        )
    }
}
