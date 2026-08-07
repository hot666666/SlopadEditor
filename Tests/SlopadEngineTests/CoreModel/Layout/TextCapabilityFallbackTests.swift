import SlopadCoreModel
import Testing

// MARK: - Capability Fallbacks

// Each adopts one capability and implements only that capability's non-defaulted members.
// If a documented fallback ever moves back onto the composed protocol, these stop
// compiling — which is the point. A backend that adopts a single capability must still
// receive the logical fallback rather than having to reimplement text segmentation.

private struct NavigationOnly: TextNavigationResolving {}

private struct DeletionOnly: TextDeletionResolving {}

private struct GeometryOnly: TextGeometryResolving {
    func textFrame(for request: BlockMeasureRequest, measuredHeight: Double?) -> EditorRect {
        EditorRect(x: 0, y: 0, width: request.availableWidth, height: measuredHeight ?? 1)
    }
    func lineFragments(for request: BlockMeasureRequest) -> [LineFragmentSnapshot] { [] }
    func caretRect(for position: TextPosition, in request: BlockMeasureRequest) -> EditorRect? {
        EditorRect(x: Double(position.offset), y: 0, width: 1, height: 1)
    }
    func selectionRects(for range: TextRange, in request: BlockMeasureRequest) -> [EditorRect] { [] }
    func textPosition(at point: EditorPoint, in request: BlockMeasureRequest) -> TextPosition {
        TextPosition(blockID: request.blockID, offset: Int(point.x))
    }
}

@Suite("좁은 계약의 논리적 폴백")
struct TextCapabilityFallbackTests {
    private let request = BlockMeasureRequest(
        blockID: "block", text: "hello world", kind: .paragraph, availableWidth: 320, depth: 0)

    @Test("navigation만 채택해도 기본 이동이 동작한다")
    func navigationOnlyGetsFallback() {
        // Given
        let backend = NavigationOnly()
        let caret = TextPosition(blockID: "block", offset: 0)

        // When
        let resolution = backend.navigate(
            selection: TextSelection(anchor: caret, focus: caret),
            context: nil, direction: .forward, destination: .character,
            extending: false, in: request)

        // Then
        guard case .selection(let moved, _) = resolution else {
            Issue.record("selection을 기대했지만 \(resolution)")
            return
        }
        #expect(moved.focus.offset == 1)
    }

    @Test("navigation만 채택해도 단어 범위를 얻는다")
    func navigationOnlyResolvesWords() {
        // Given
        let backend = NavigationOnly()

        // When
        let word = backend.wordRange(
            containing: TextPosition(blockID: "block", offset: 2), in: request)

        // Then
        #expect(word == TextRange(0, 5))
    }

    @Test("deletion만 채택해도 삭제 범위를 얻는다")
    func deletionOnlyResolvesRange() {
        // Given
        let backend = DeletionOnly()
        let caret = TextPosition(blockID: "block", offset: 3)

        // When
        let range = backend.deletionRange(
            for: TextSelection(anchor: caret, focus: caret),
            direction: .backward, destination: .character, in: request)

        // Then
        #expect(range == TextRange(2, 3))
    }

    @Test("geometry만 채택해도 hit test가 textPosition으로 위임된다")
    func geometryOnlyGetsHitTestFallback() {
        // Given
        let backend = GeometryOnly()

        // When
        let hit = backend.textHitTest(at: EditorPoint(x: 4, y: 0), in: request)

        // Then
        #expect(hit?.position.offset == 4)
    }
}
