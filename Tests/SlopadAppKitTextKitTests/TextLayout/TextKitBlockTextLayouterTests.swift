import Testing

@testable import SlopadAppKitTextKit
@testable import SlopadCoreModel

@Suite("TextKit 블록 텍스트 레이아웃")
struct TextKitBlockTextLayouterTests {
    @Test("긴 문단을 좁은 폭으로 측정하면 높이가 증가한다")
    func givenLongText_whenMeasuringNarrowerWidth_thenMeasuredHeightIncreases() {
        // Given
        let textLayouter = TextKitBlockTextLayouter()
        let text = "TextKit measurement should wrap this paragraph into multiple visual lines."
        let wideRequest = makeMeasureRequest(text: text, width: 420)
        let narrowRequest = makeMeasureRequest(text: text, width: 120)

        // When
        let wide = textLayouter.measure(wideRequest)
        let narrow = textLayouter.measure(narrowRequest)

        // Then
        #expect(narrow.height > wide.height)
    }

    @Test("마지막 줄바꿈이 있으면 빈 마지막 줄도 높이에 반영된다")
    func givenTrailingNewline_whenMeasuring_thenEmptyFinalLineContributesHeight() {
        // Given
        let textLayouter = TextKitBlockTextLayouter(style: TextKitEditorStyle(fontSize: 24))
        let width = 280.0
        let singleLineRequest = makeMeasureRequest(text: "Line", width: width)
        let trailingLineRequest = makeMeasureRequest(text: "Line\n", width: width)
        let explicitLineRequest = makeMeasureRequest(text: "Line\nA", width: width)

        // When
        let singleLine = textLayouter.measure(singleLineRequest)
        let trailingLine = textLayouter.measure(trailingLineRequest)
        let explicitLine = textLayouter.measure(explicitLineRequest)

        // Then
        #expect(trailingLine.height > singleLine.height)
        #expect(abs(trailingLine.height - explicitLine.height) <= 1)
    }

    @Test("인라인 코드 스타일은 줄바꿈과 측정 높이에 반영된다")
    func givenInlineCodeRun_whenMeasuring_thenInlineStylingAffectsWrapping() {
        // Given
        let textLayouter = TextKitBlockTextLayouter(style: TextKitEditorStyle(fontSize: 18))
        let text = String(repeating: "i", count: 90)
        let range = TextRange(0, text.count)
        let plainRequest = makeMeasureRequest(
            text: text,
            width: 90,
            inlineRuns: [BlockContent.InlineRun(range: range, text: text, marks: [])]
        )
        let codeRequest = makeMeasureRequest(
            text: text,
            width: 90,
            inlineRuns: [BlockContent.InlineRun(range: range, text: text, marks: [.code])]
        )

        // When
        let plain = textLayouter.measure(plainRequest)
        let code = textLayouter.measure(codeRequest)

        // Then
        #expect(code.height > plain.height)
    }

    @Test("거터 폭이 커지면 같은 블록 텍스트의 측정 높이가 증가한다")
    func largerGutterWidthIncreasesMeasuredHeight() {
        // Given
        let text =
            "A passive block render reserves gutter and chrome before TextKit measures wrapping."
        let compact = TextKitBlockTextLayouter(
            style: TextKitEditorStyle(gutterWidth: 24, contentHorizontalPadding: 8)
        )
        let wideGutter = TextKitBlockTextLayouter(
            style: TextKitEditorStyle(gutterWidth: 96, contentHorizontalPadding: 8)
        )
        let request = makeMeasureRequest(text: text, width: 240)

        // When
        let compactHeight = compact.measure(request).height
        let wideGutterHeight = wideGutter.measure(request).height

        // Then
        #expect(wideGutterHeight >= compactHeight)
    }

    @Test("블록 내부 좌표를 텍스트 위치로 변환한다")
    func pointMapsToTextPosition() throws {
        // Given
        let provider = TextKitBlockTextLayouter()
        let request = makeMeasureRequest(text: "hello world", width: 260)
        let caret = try #require(
            provider.caretRect(
                for: TextPosition(blockID: "block", offset: 5),
                in: request
            ))
        let point = EditorPoint(x: caret.midX + 1, y: caret.midY)

        // When
        let position = provider.textPosition(at: point, in: request)

        // Then
        #expect(position.blockID == "block")
        #expect(abs(position.offset - 5) <= 1)
    }

    @Test("텍스트 범위에서 선택 영역 사각형을 생성한다")
    func textRangeProducesSelectionRects() {
        // Given
        let provider = TextKitBlockTextLayouter()
        let request = makeMeasureRequest(text: "selection rect", width: 260)

        // When
        let rects = provider.selectionRects(for: TextRange(0, 9), in: request)

        // Then
        #expect(!rects.isEmpty)
        #expect(rects.allSatisfy { $0.width >= 0 && $0.height > 0 })
    }

    @Test("텍스트킷 줄 조각은 블록 식별자와 텍스트 범위를 유지한다")
    func lineFragmentsPreserveBlockIDAndTextRange() throws {
        // Given
        let provider = TextKitBlockTextLayouter()
        let request = makeMeasureRequest(text: "line one line two line three", width: 120)

        // When
        let fragments = provider.lineFragments(for: request)

        // Then
        #expect(!fragments.isEmpty)
        #expect(fragments.allSatisfy { $0.blockID == "block" })
        let first = try #require(fragments.first)
        #expect(first.range.lowerBound == 0)
    }

    @Test("빈 문서 placeholder와 마지막 줄바꿈 sentinel을 줄 범위로 노출하지 않는다")
    func lineFragmentsStayWithinCanonicalText() {
        // Given
        let provider = TextKitBlockTextLayouter()
        let emptyRequest = makeMeasureRequest(text: "", width: 120)
        let trailingNewlineRequest = makeMeasureRequest(text: "A\n", width: 120)

        // When
        let emptyFragments = provider.lineFragments(for: emptyRequest)
        let trailingNewlineFragments = provider.lineFragments(for: trailingNewlineRequest)

        // Then
        #expect(!emptyFragments.isEmpty)
        #expect(!trailingNewlineFragments.isEmpty)
        #expect(emptyFragments.allSatisfy { $0.range == .point(0) })
        #expect(
            trailingNewlineFragments.allSatisfy {
                $0.range.lowerBound >= 0
                    && $0.range.upperBound <= trailingNewlineRequest.text.count
            }
        )
    }

}

private func makeMeasureRequest(
    text: String,
    width: Double,
    kind: BlockKind = .paragraph,
    inlineRuns: [BlockContent.InlineRun]? = nil
) -> BlockMeasureRequest {
    BlockMeasureRequest(
        blockID: "block",
        text: text,
        kind: kind,
        inlineRuns: inlineRuns ?? BlockContent(text: text).inlineRuns,
        availableWidth: width,
        depth: 0
    )
}
