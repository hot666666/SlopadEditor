import AppKit
import Testing

@testable import SlopadAppKitTextKit
@testable import SlopadCoreModel

@Suite("TextKit 네이티브 텍스트 탐색")
struct TextKitTextNavigationTests {
    @Test("혼합 bidi 문장에서 시각적 오른쪽 이동 순서를 유지한다")
    func mixedBidiUsesVisualOrder() throws {
        // Given
        let provider = TextKitBlockTextLayouter()
        let request = makeNavigationRequest(text: "abc אבג def")
        let expectedOffsets = [1, 2, 3, 4, 6, 5, 7, 8]
        var selection = caretSelection(offset: 0)
        var context: TextNavigationContext?
        var offsets: [Int] = []

        // When
        for _ in expectedOffsets {
            let resolution = provider.navigate(
                selection: selection,
                context: context,
                direction: .right,
                destination: .character,
                extending: false,
                in: request
            )
            selection = try #require(resolution.selection)
            context = resolution.navigationContext
            offsets.append(selection.focus.offset)

            // Then
            #expect(selection.anchor == selection.focus)
            #expect(selection.focus.affinity == .downstream)
            #expect((0...request.text.count).contains(selection.focus.offset))
        }

        // Then
        #expect(offsets == expectedOffsets)
        #expect(context != nil)
    }

    @Test("컨테이너 폭 변경 후에도 혼합 bidi 시각 순서를 다시 계산한다")
    func widthChangeRefreshesVisualOrder() throws {
        // Given
        let provider = TextKitBlockTextLayouter()
        let narrowRequest = makeNavigationRequest(text: "warm up layout", width: 120)
        let bidiRequest = makeNavigationRequest(text: "abc אבג def", width: 360)
        _ = provider.measure(narrowRequest)

        // When
        let moved = try #require(
            provider.navigate(
                selection: caretSelection(offset: 4),
                context: nil,
                direction: .right,
                destination: .character,
                extending: false,
                in: bidiRequest
            ).selection
        )

        // Then
        #expect(moved.focus.offset == 6)
        #expect(moved.focus.affinity == .downstream)
    }

    @Test("혼합 bidi의 transient inline context는 alternate caret과 다음 이동을 보존한다")
    func navigationContextPreservesAlternateBidiCaret() throws {
        // Given
        let provider = TextKitBlockTextLayouter()
        let request = makeNavigationRequest(text: "abc אבג def")
        var selection = caretSelection(offset: 0)
        var context: TextNavigationContext?
        for expectedOffset in [1, 2, 3, 4, 6, 5, 7] {
            let resolution = provider.navigate(
                selection: selection,
                context: context,
                direction: .right,
                destination: .character,
                extending: false,
                in: request
            )
            selection = try #require(resolution.selection)
            context = resolution.navigationContext
            #expect(selection.focus.offset == expectedOffset)
        }
        let resolvedContext = try #require(context)
        let caretInlineOffset = try #require(resolvedContext.caretInlineOffset)
        _ = provider.measure(makeNavigationRequest(text: "other layout", width: 180))

        // When
        let ordinaryRect = try #require(provider.caretRect(for: selection.focus, in: request))
        let contextualRect = try #require(
            provider.caretRect(
                for: selection.focus,
                navigationContext: resolvedContext,
                in: request
            )
        )
        let hitResult = try #require(
            provider.textHitTest(
                at: EditorPoint(x: contextualRect.midX, y: contextualRect.midY),
                in: request
            )
        )
        let nextResolution = provider.navigate(
            selection: selection,
            context: resolvedContext,
            direction: .right,
            destination: .character,
            extending: false,
            in: request
        )
        let nextSelection = try #require(nextResolution.selection)

        // Then
        let textFrame = provider.textFrame(for: request)
        #expect(abs(contextualRect.minX - ordinaryRect.minX) > 1)
        #expect(abs(contextualRect.minX - (textFrame.minX + caretInlineOffset)) < 0.5)
        #expect(hitResult.position == selection.focus)
        #expect(hitResult.navigationContext?.caretInlineOffset != nil)
        #expect(
            abs(
                (hitResult.navigationContext?.caretInlineOffset ?? 0)
                    - caretInlineOffset
            ) < 0.5
        )
        #expect(nextSelection.focus.offset == 8)
    }

    @Test("LTR 오른쪽 이동 context는 ordinary caret을 문단 시작으로 되돌리지 않는다")
    func ltrContextDoesNotMoveCaretToLineStart() throws {
        // Given
        let provider = TextKitBlockTextLayouter()
        let request = makeNavigationRequest(text: "abcdef")
        let resolution = provider.navigate(
            selection: caretSelection(offset: 0),
            context: nil,
            direction: .right,
            destination: .character,
            extending: false,
            in: request
        )
        let selection = try #require(resolution.selection)
        let context = try #require(resolution.navigationContext)

        // When
        let ordinaryRect = try #require(provider.caretRect(for: selection.focus, in: request))
        let contextualRect = try #require(
            provider.caretRect(
                for: selection.focus,
                navigationContext: context,
                in: request
            )
        )

        // Then
        let textFrame = provider.textFrame(for: request)
        #expect(selection.focus.offset == 1)
        #expect(contextualRect.minX > textFrame.minX)
        #expect(abs(contextualRect.minX - ordinaryRect.minX) < 0.5)
    }

    @Test("native point hit-test는 nonzero preferred offset과 필요한 caret override만 반환한다")
    func pointHitTestReturnsPreferredInlineOffset() throws {
        // Given
        let provider = TextKitBlockTextLayouter()
        let request = makeNavigationRequest(text: "abcdef")
        let position = TextPosition(blockID: "block", offset: 5)
        let caretRect = try #require(provider.caretRect(for: position, in: request))

        // When
        let result = try #require(
            provider.textHitTest(
                at: EditorPoint(x: caretRect.midX, y: caretRect.midY),
                in: request
            )
        )

        // Then
        let context = try #require(result.navigationContext)
        #expect(result.position == position)
        #expect(context.preferredInlineOffset > 0)
        #expect(context.caretInlineOffset == nil)
    }

    @Test("시각적 이동 결과의 upstream과 downstream affinity를 보존한다")
    func visualMovementPreservesAffinity() throws {
        // Given
        let provider = TextKitBlockTextLayouter()
        let request = makeNavigationRequest(text: "abc אבג def")

        // When
        let movedRight = try #require(
            provider.navigate(
                selection: caretSelection(offset: 4),
                context: nil,
                direction: .right,
                destination: .character,
                extending: false,
                in: request
            ).selection
        )
        let movedLeft = try #require(
            provider.navigate(
                selection: caretSelection(offset: 4),
                context: nil,
                direction: .left,
                destination: .character,
                extending: false,
                in: request
            ).selection
        )

        // Then
        #expect(movedRight.focus == TextPosition(blockID: "block", offset: 6, affinity: .downstream))
        #expect(movedLeft.focus == TextPosition(blockID: "block", offset: 3, affinity: .upstream))
    }

    @Test("순수 RTL 문장은 물리적 좌우 이동으로 왕복한다")
    func pureRTLUsesPhysicalDirections() throws {
        // Given
        let text = "אבג"
        let provider = TextKitBlockTextLayouter()
        let request = makeNavigationRequest(text: text)
        var selection = caretSelection(offset: 0)
        var context: TextNavigationContext?
        var leftOffsets: [Int] = []
        var rightOffsets: [Int] = []

        // When
        for _ in 0..<text.count {
            let resolution = provider.navigate(
                selection: selection,
                context: context,
                direction: .left,
                destination: .character,
                extending: false,
                in: request
            )
            selection = try #require(resolution.selection)
            context = resolution.navigationContext
            leftOffsets.append(selection.focus.offset)
        }
        for _ in 0..<text.count {
            let resolution = provider.navigate(
                selection: selection,
                context: context,
                direction: .right,
                destination: .character,
                extending: false,
                in: request
            )
            selection = try #require(resolution.selection)
            context = resolution.navigationContext
            rightOffsets.append(selection.focus.offset)
        }

        // Then
        #expect(leftOffsets == [1, 2, 3])
        #expect(rightOffsets == [2, 1, 0])
        #expect(selection.anchor == selection.focus)
        #expect((leftOffsets + rightOffsets).allSatisfy { (0...text.count).contains($0) })
    }

    @Test("LTR과 RTL의 물리적 바깥 이동은 해당 논리 블록 경계를 반환한다")
    func physicalOuterEdgesReturnLogicalBoundaries() {
        // Given
        let provider = TextKitBlockTextLayouter()
        let ltrRequest = makeNavigationRequest(text: "abc")
        let rtlRequest = makeNavigationRequest(text: "אבג")

        // When
        let ltrStart = provider.navigate(
            selection: caretSelection(offset: 0),
            context: nil,
            direction: .left,
            destination: .character,
            extending: false,
            in: ltrRequest
        )
        let ltrEnd = provider.navigate(
            selection: caretSelection(offset: ltrRequest.text.count),
            context: nil,
            direction: .right,
            destination: .character,
            extending: false,
            in: ltrRequest
        )
        let rtlStart = provider.navigate(
            selection: caretSelection(offset: 0),
            context: nil,
            direction: .right,
            destination: .character,
            extending: false,
            in: rtlRequest
        )
        let rtlEnd = provider.navigate(
            selection: caretSelection(offset: rtlRequest.text.count),
            context: nil,
            direction: .left,
            destination: .character,
            extending: false,
            in: rtlRequest
        )

        // Then
        #expect(ltrStart == .boundary(.start))
        #expect(ltrEnd == .boundary(.end))
        #expect(rtlStart == .boundary(.start))
        #expect(rtlEnd == .boundary(.end))
    }

    @Test("CJK 단어 탐색과 삭제는 TextKit 단어 경계를 사용한다")
    func cjkUsesNativeWordBoundaries() throws {
        // Given
        let text = "你好世界"
        let provider = TextKitBlockTextLayouter(
            style: TextKitEditorStyle(languageIdentifier: "zh-Hans")
        )
        let request = makeNavigationRequest(text: text)

        // When
        let moved = try #require(
            provider.navigate(
                selection: caretSelection(offset: 0),
                context: nil,
                direction: .right,
                destination: .word,
                extending: false,
                in: request
            ).selection
        )
        let enclosingWord = try #require(
            provider.wordRange(
                containing: TextPosition(blockID: "block", offset: 2),
                in: request
            )
        )
        let deletion = try #require(
            provider.deletionRange(
                for: caretSelection(offset: text.count),
                direction: .backward,
                destination: .word,
                in: request
            )
        )

        // Then
        #expect(moved.focus.offset == 1)
        #expect(enclosingWord.contains(2))
        #expect(enclosingWord.lowerBound >= 0)
        #expect(enclosingWord.upperBound <= text.count)
        #expect(deletion.lowerBound > 0)
        #expect(deletion.upperBound == text.count)
    }

    @Test("결합 문자와 ZWJ 이모지 내부 UTF-16 위치를 노출하지 않는다")
    func graphemeNavigationDoesNotLeakUTF16Offsets() throws {
        // Given
        let text = "e\u{301}👨‍👩‍👧‍👦X"
        let provider = TextKitBlockTextLayouter()
        let request = makeNavigationRequest(text: text)
        var selection = caretSelection(offset: 0)
        var offsets: [Int] = []

        // When
        for _ in 0..<text.count {
            selection = try #require(
                provider.navigate(
                    selection: selection,
                    context: nil,
                    direction: .forward,
                    destination: .character,
                    extending: false,
                    in: request
                ).selection
            )
            offsets.append(selection.focus.offset)
        }
        let deletion = provider.deletionRange(
            for: caretSelection(offset: 2),
            direction: .backward,
            destination: .character,
            in: request
        )

        // Then
        #expect(text.count == 3)
        #expect(offsets == [1, 2, 3])
        #expect(deletion == TextRange(1, 2))
        #expect(offsets.allSatisfy { (0...text.count).contains($0) })
    }

    @Test("prepared request가 바뀌면 grapheme과 UTF-16 인덱스 맵도 함께 교체한다")
    func preparedRequestReplacesIndexMap() throws {
        // Given
        let provider = TextKitBlockTextLayouter()
        let unicodeRequest = makeNavigationRequest(text: "👨‍👩‍👧‍👦X")
        let asciiRequest = makeNavigationRequest(text: "AB")
        _ = try #require(
            provider.caretRect(
                for: TextPosition(blockID: "block", offset: 1),
                in: unicodeRequest
            )
        )

        // When
        let asciiCaret = try #require(
            provider.caretRect(
                for: TextPosition(blockID: "block", offset: 1),
                in: asciiRequest
            )
        )
        let asciiHit = try #require(
            provider.textHitTest(
                at: EditorPoint(x: asciiCaret.midX, y: asciiCaret.midY),
                in: asciiRequest
            )
        )
        let unicodeCaret = try #require(
            provider.caretRect(
                for: TextPosition(blockID: "block", offset: 1),
                in: unicodeRequest
            )
        )
        let unicodeHit = try #require(
            provider.textHitTest(
                at: EditorPoint(x: unicodeCaret.midX, y: unicodeCaret.midY),
                in: unicodeRequest
            )
        )

        // Then
        #expect(asciiHit.position.offset == 1)
        #expect(unicodeHit.position.offset == 1)
    }

    @Test("확장 탐색은 비어 있지 않은 선택의 anchor 방향을 유지한다")
    func extendingSelectionPreservesAnchorOrientation() throws {
        // Given
        let provider = TextKitBlockTextLayouter()
        let request = makeNavigationRequest(text: "abcdef")
        let forwardSelection = TextSelection(
            anchor: TextPosition(blockID: "block", offset: 0),
            focus: TextPosition(blockID: "block", offset: 3)
        )
        let reverseSelection = TextSelection(
            anchor: TextPosition(blockID: "block", offset: 3),
            focus: TextPosition(blockID: "block", offset: 0)
        )

        // When
        let forwardResolution = provider.navigate(
            selection: forwardSelection,
            context: nil,
            direction: .backward,
            destination: .character,
            extending: true,
            in: request
        )
        let reverseResolution = provider.navigate(
            selection: reverseSelection,
            context: nil,
            direction: .forward,
            destination: .character,
            extending: true,
            in: request
        )
        let forwardResult = try #require(forwardResolution.selection)
        let reverseResult = try #require(reverseResolution.selection)

        // Then
        #expect(forwardResult.anchor.offset == 0)
        #expect(forwardResult.focus.offset == 2)
        #expect(reverseResult.anchor.offset == 3)
        #expect(reverseResult.focus.offset == 1)
        #expect(forwardResolution.navigationContext?.caretInlineOffset == nil)
        #expect(reverseResolution.navigationContext?.caretInlineOffset == nil)
    }

    @Test("마지막 줄바꿈 sentinel은 문서 offset이나 단어 범위로 노출되지 않는다")
    func trailingNewlineSentinelStaysInternal() {
        // Given
        let text = "A\n"
        let provider = TextKitBlockTextLayouter()
        let request = makeNavigationRequest(text: text)
        let end = caretSelection(offset: text.count)

        // When
        let navigation = provider.navigate(
            selection: end,
            context: nil,
            direction: .right,
            destination: .character,
            extending: false,
            in: request
        )
        let word = provider.wordRange(containing: end.focus, in: request)
        let deletion = provider.deletionRange(
            for: end,
            direction: .backward,
            destination: .word,
            in: request
        )

        // Then
        #expect(navigation == .boundary(.end))
        #expect(word == .point(text.count))
        #expect(deletion == TextRange(0, text.count))
    }

    @Test("빈 문서 placeholder는 시작과 끝 경계 밖으로 노출되지 않는다")
    func emptyPlaceholderStaysInternal() {
        // Given
        let provider = TextKitBlockTextLayouter()
        let request = makeNavigationRequest(text: "")
        let caret = caretSelection(offset: 0)

        // When
        let left = provider.navigate(
            selection: caret,
            context: nil,
            direction: .left,
            destination: .character,
            extending: false,
            in: request
        )
        let right = provider.navigate(
            selection: caret,
            context: nil,
            direction: .right,
            destination: .character,
            extending: false,
            in: request
        )
        let word = provider.wordRange(containing: caret.focus, in: request)
        let deletion = provider.deletionRange(
            for: caret,
            direction: .backward,
            destination: .word,
            in: request
        )

        // Then
        #expect(left == .boundary(.start))
        #expect(right == .boundary(.end))
        #expect(word == .point(0))
        #expect(deletion == nil)
    }

    @Test("native candidate 변환 실패는 논리 시작과 끝에서도 블록 경계가 아니다")
    func invalidCandidateDoesNotProduceBoundary() {
        // Given
        let request = makeNavigationRequest(text: "abc")
        let start = caretSelection(offset: 0)
        let end = caretSelection(offset: request.text.count)

        // When
        let startResolution = textKitNavigationResolution(
            for: .invalidCandidate,
            selection: start,
            direction: .backward,
            request: request,
            graphemeCount: request.text.count
        )
        let endResolution = textKitNavigationResolution(
            for: .invalidCandidate,
            selection: end,
            direction: .forward,
            request: request,
            graphemeCount: request.text.count
        )

        // Then
        #expect(startResolution == .unchanged)
        #expect(endResolution == .unchanged)
    }

    @Test("native destination 부재는 현재 블록의 논리 시작과 끝에서만 경계가 된다")
    func missingDestinationResolvesOnlyAtLogicalEdges() {
        // Given
        let request = makeNavigationRequest(text: "abc")

        // When
        let startResolution = textKitNavigationResolution(
            for: .destinationMissing,
            selection: caretSelection(offset: 0),
            direction: .backward,
            request: request,
            graphemeCount: request.text.count
        )
        let interiorResolution = textKitNavigationResolution(
            for: .destinationMissing,
            selection: caretSelection(offset: 1),
            direction: .forward,
            request: request,
            graphemeCount: request.text.count
        )
        let endResolution = textKitNavigationResolution(
            for: .destinationMissing,
            selection: caretSelection(offset: request.text.count),
            direction: .forward,
            request: request,
            graphemeCount: request.text.count
        )

        // Then
        #expect(startResolution == .boundary(.start))
        #expect(interiorResolution == .unchanged)
        #expect(endResolution == .boundary(.end))
    }

    @Test("다른 블록 선택의 native destination 부재는 현재 블록 경계가 아니다")
    func crossBlockMissingDestinationDoesNotProduceBoundary() {
        // Given
        let request = makeNavigationRequest(text: "abc")
        let otherBlockPosition = TextPosition(blockID: "other", offset: 0)
        let selection = TextSelection(
            anchor: otherBlockPosition,
            focus: otherBlockPosition
        )

        // When
        let resolution = textKitNavigationResolution(
            for: .destinationMissing,
            selection: selection,
            direction: .backward,
            request: request,
            graphemeCount: request.text.count
        )

        // Then
        #expect(resolution == .unchanged)
    }

    @Test("줄바꿈 경계의 caret affinity는 서로 다른 geometry와 hit-test 결과를 만든다")
    func caretAffinitySelectsWrappedLineGeometry() throws {
        // Given
        let provider = TextKitBlockTextLayouter(style: TextKitEditorStyle(fontSize: 18))
        let request = makeNavigationRequest(
            text: "alpha beta gamma delta epsilon zeta eta theta",
            width: 150
        )
        let fragments = provider.lineFragments(for: request)
        let first = try #require(fragments.first)
        _ = try #require(fragments.dropFirst().first)
        let boundaryOffset = first.range.upperBound
        let upstreamPosition = TextPosition(
            blockID: "block",
            offset: boundaryOffset,
            affinity: .upstream
        )
        let downstreamPosition = TextPosition(
            blockID: "block",
            offset: boundaryOffset,
            affinity: .downstream
        )

        // When
        let upstreamRect = try #require(provider.caretRect(for: upstreamPosition, in: request))
        let downstreamRect = try #require(provider.caretRect(for: downstreamPosition, in: request))
        let upstreamHit = provider.textPosition(
            at: EditorPoint(x: upstreamRect.midX, y: upstreamRect.midY),
            in: request
        )
        let downstreamHit = provider.textPosition(
            at: EditorPoint(x: downstreamRect.midX, y: downstreamRect.midY),
            in: request
        )

        // Then
        #expect(upstreamRect.midY < downstreamRect.midY)
        #expect(upstreamHit == upstreamPosition)
        #expect(downstreamHit == downstreamPosition)
    }

    @Test("선택적 BCP-47 언어 식별자를 기본 및 인라인 속성에 적용한다")
    func languageIdentifierIsAppliedToAttributedText() {
        // Given
        let text = "日本語"
        let provider = TextKitBlockTextLayouter(
            style: TextKitEditorStyle(languageIdentifier: "ja-JP")
        )
        let request = makeNavigationRequest(
            text: text,
            inlineRuns: [
                BlockContent.InlineRun(range: TextRange(0, text.count), text: text, marks: [.bold])
            ]
        )

        // When
        let attributed = provider.attributedString(for: request)
        let firstLanguage = attributed.attribute(.languageIdentifier, at: 0, effectiveRange: nil)
        let lastLanguage = attributed.attribute(
            .languageIdentifier,
            at: attributed.length - 1,
            effectiveRange: nil
        )

        // Then
        #expect(firstLanguage as? String == "ja-JP")
        #expect(lastLanguage as? String == "ja-JP")
    }
}

private extension TextNavigationResolution {
    var selection: TextSelection? {
        guard case .selection(let selection, _) = self else { return nil }
        return selection
    }

    var navigationContext: TextNavigationContext? {
        guard case .selection(_, let context) = self else { return nil }
        return context
    }
}

private func caretSelection(
    offset: Int,
    affinity: TextAffinity = .downstream
) -> TextSelection {
    let position = TextPosition(blockID: "block", offset: offset, affinity: affinity)
    return TextSelection(anchor: position, focus: position)
}

private func makeNavigationRequest(
    text: String,
    width: Double = 360,
    inlineRuns: [BlockContent.InlineRun]? = nil
) -> BlockMeasureRequest {
    BlockMeasureRequest(
        blockID: "block",
        text: text,
        kind: .paragraph,
        inlineRuns: inlineRuns ?? BlockContent(text: text).inlineRuns,
        availableWidth: width,
        depth: 0
    )
}
