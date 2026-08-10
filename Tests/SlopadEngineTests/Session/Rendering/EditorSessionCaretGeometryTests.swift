import SlopadCoreModel
import Testing

@testable import SlopadEngine

// MARK: - Session-published caret geometry

@Suite("Session 이 발행하는 caret 기하")
struct EditorSessionCaretGeometryTests {
    @Test("활성 입력 서술자가 caret 사각형을 문서 좌표로 싣는다")
    func publishesCaretRect() {
        // Given
        let session = makeSession(text: "Body", caretAt: 2)

        // When
        let snapshot = session.render(in: viewport)

        // Then: 어댑터가 백엔드에 다시 묻지 않고 그릴 수 있어야 한다.
        let descriptor = snapshot.activeTextInput
        #expect(descriptor != nil)
        #expect(descriptor?.caretRect != nil)
    }

    @Test("caret만 있으면 선택 사각형은 비어 있다")
    func caretOnlyHasNoSelectionRects() {
        // Given
        let session = makeSession(text: "Body", caretAt: 2)

        // When
        let snapshot = session.render(in: viewport)

        // Then
        #expect(snapshot.activeTextInput?.selectionRects.isEmpty == true)
    }

    @Test("범위를 선택하면 선택 사각형이 실린다")
    func publishesSelectionRects() {
        // Given
        let blockID: BlockID = "block"
        let session = EditorSession(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "Body"))],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 0),
                    focus: TextPosition(blockID: blockID, offset: 4)
                )),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let snapshot = session.render(in: viewport)

        // Then
        #expect(snapshot.activeTextInput?.selectionRects.isEmpty == false)
    }

    @Test("caret 사각형이 블록 프레임을 따라 이동한다")
    func caretRectFollowsTheBlockFrame() {
        // Given: 두 번째 블록의 caret 은 첫 블록 아래에 있어야 한다 — 문서 좌표라는 뜻이다.
        let first: BlockID = "a"
        let second: BlockID = "b"
        let session = EditorSession(
            blocks: [
                EditorBlockInput(id: first, content: BlockContent(text: "First")),
                EditorBlockInput(id: second, content: BlockContent(text: "Second")),
            ],
            selection: .caret(blockID: second, offset: 0),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let snapshot = session.render(in: viewport)
        let firstFrame = snapshot.visibleBlocks.first { $0.id == first }?.frame

        // Then
        let caret = snapshot.activeTextInput?.caretRect
        #expect(caret != nil)
        #expect((caret?.y ?? 0) >= (firstFrame?.y ?? 0) + (firstFrame?.height ?? 0) - 1)
    }

    @Test("수렴 렌더가 반복돼도 기하를 다시 계산하지 않는다")
    func reusesGeometryAcrossConvergenceRenders() {
        // Given: 어댑터는 표면이 수렴할 때까지 최대 32회 렌더하고 마지막에 한 번만 그린다.
        // 렌더마다 다시 계산하면 긴 블록을 드래그 선택할 때 줄 조각을 매번 훑게 된다.
        let counting = CountingGeometryLayouter()
        let blockID: BlockID = "block"
        let session = EditorSession(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "Body text"))],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 0),
                    focus: TextPosition(blockID: blockID, offset: 9)
                )),
            textLayouter: counting
        )

        // When: 같은 뷰포트로 여러 번 렌더한다.
        for _ in 0..<5 { _ = session.render(in: viewport) }

        // Then
        #expect(counting.selectionRectCalls == 1)
        #expect(counting.caretRectCalls == 1)
    }

    @Test("백엔드를 교체하면 기하를 다시 계산한다")
    func recomputesAfterBackendReplacement() {
        // Given: 스타일 교체는 글리프 지표를 바꾸면서 텍스트·폭·깊이·선택·caret 위치는
        // 그대로 둘 수 있다. 메모 키는 "무엇을 물었는가"만 담고 "누가 답했는가"는 담지
        // 못하므로, 교체 시 버리지 않으면 이전 폰트로 잰 사각형을 계속 돌려준다.
        let first = CountingGeometryLayouter()
        let blockID: BlockID = "block"
        let session = EditorSession(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "Body text"))],
            selection: .caret(blockID: blockID, offset: 0),
            textLayouter: first
        )
        _ = session.render(in: viewport)
        #expect(first.caretRectCalls == 1)

        // When: 키에 들어가는 값은 하나도 바꾸지 않고 백엔드만 갈아끼운다.
        let second = CountingGeometryLayouter()
        session.replaceTextLayoutBackend(with: second)
        _ = session.render(in: viewport)

        // Then
        #expect(second.caretRectCalls == 1)
    }

    @Test("선택이 바뀌면 기하를 다시 계산한다")
    func recomputesWhenTheSelectionChanges() {
        // Given
        let counting = CountingGeometryLayouter()
        let blockID: BlockID = "block"
        let session = EditorSession(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "Body text"))],
            selection: .caret(blockID: blockID, offset: 0),
            textLayouter: counting
        )
        _ = session.render(in: viewport)
        let before = counting.caretRectCalls

        // When
        _ = session.handleInput(.command(.moveToTextEnd))
        _ = session.render(in: viewport)

        // Then
        #expect(counting.caretRectCalls > before)
    }

    @Test("줄 조각 사각형을 문서 좌표로 질의할 수 있다")
    func exposesLineFragmentRects() {
        // Given: 어댑터가 "이 점이 텍스트에 닿는가"를 백엔드 없이 물을 수 있어야 한다.
        let session = makeSession(text: "Body", caretAt: 0)
        let snapshot = session.render(in: viewport)
        let rendered = snapshot.visibleBlocks.first

        // When
        let rects = rendered.map { session.textLineFragmentRects(in: $0.textRender) } ?? []

        // Then
        #expect(!rects.isEmpty)
        #expect(rects.allSatisfy { $0.height > 0 })
    }

    @Test("TN toolbar 기하는 visible fragment만 합치고 화면 밖 endpoint를 표시한다")
    func givenLongCrossBlockSelection_whenRenderingMiddleViewport_thenBoundsStayVisibleOnly() {
        // Given
        let blockIDs = (0..<100).map { BlockID("block-\($0)") }
        let session = EditorSession(
            blocks: blockIDs.map {
                EditorBlockInput(id: $0, content: .init(text: "visible text"))
            },
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockIDs[0], offset: 1),
                    focus: TextPosition(blockID: blockIDs[99], offset: 5)
                )
            ),
            textLayouter: DeterministicBlockTextLayouter()
        )
        _ = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 1_000))

        // When
        let viewport = EditorViewport(width: 240, scrollY: 1_000, height: 120)
        let presentation = session.render(in: viewport).selectionPresentation

        // Then
        let bounds = presentation.visibleBounds
        #expect(bounds != nil)
        #expect((bounds?.minY ?? 0) >= viewport.scrollY)
        #expect((bounds?.maxY ?? 0) <= viewport.scrollY + viewport.height)
        #expect(presentation.focusRect == nil)
        #expect(!presentation.isAnchorVisible)
        #expect(!presentation.isFocusVisible)
        #expect(presentation.visibleTextSelections.count < blockIDs.count)
    }

    @Test("separator-only TN은 logical selection이어도 toolbar anchor 기하를 만들지 않는다")
    func givenSeparatorOnlyTextSelection_whenRendering_thenNoUsableToolbarGeometryExists() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            blocks: [
                EditorBlockInput(id: a, content: .init(text: "A")),
                EditorBlockInput(id: b, content: .init(text: "B")),
            ],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: a, offset: 1),
                    focus: TextPosition(blockID: b, offset: 0)
                )
            ),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let presentation = session.render(in: viewport).selectionPresentation

        // Then
        #expect(
            presentation.visibleTextSelections.map(\.range) == [
                TextRange.point(1), TextRange.point(0),
            ])
        #expect(presentation.visibleBounds == nil)
        #expect(presentation.focusRect == nil)
        #expect(presentation.isAnchorVisible)
        #expect(presentation.isFocusVisible)
    }

    @Test("BlockSelection toolbar 기하는 visible selected frame과 focus frame만 싣는다")
    func givenBlockSelection_whenRendering_thenVisibleFramesAndFocusAreProjected() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let session = EditorSession(
            blocks: [a, b, c].map {
                EditorBlockInput(id: $0, content: .init(text: "block"))
            },
            selection: .blocks(
                BlockSelection(blockIDs: [a, b, c], anchor: a, focus: c)
            ),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let presentation = session.render(in: viewport).selectionPresentation

        // Then
        #expect(presentation.visibleBlockSelectionIDs == Set([a, b, c]))
        #expect(presentation.visibleBounds != nil)
        #expect(presentation.focusRect != nil)
        #expect(presentation.isAnchorVisible)
        #expect(presentation.isFocusVisible)
    }

    @Test("비연속 10k BlockSelection의 stable scroll은 membership을 한 번만 만든다")
    func reusesNoncontiguousBlockSelectionMembershipAcrossStableScroll() {
        // Given
        let blockCount = 10_000
        let blocks = (0..<blockCount).map { index in
            EditorBlockInput(
                id: BlockID("block-\(index)"),
                content: .init(text: "Block \(index)")
            )
        }
        let selectedIDs = stride(from: 0, to: blockCount, by: 2).map {
            BlockID("block-\($0)")
        }
        let session = EditorSession(
            blocks: blocks,
            selection: .blocks(BlockSelection(blockIDs: selectedIDs)),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        for frame in 0..<64 {
            _ = session.render(
                in: EditorViewport(
                    width: 240,
                    scrollY: Double(frame * 1_000),
                    height: 400
                )
            )
        }

        // Then
        #expect(session.blockSelectionMembershipRebuildCount == 1)
        #expect(session.blockSelectionMembershipVisitedIDCount == selectedIDs.count)
        #expect(session.cachedBlockSelectionMembership?.blockIDs.count == selectedIDs.count)

        // When: owner가 발행한 exact selection identity가 바뀐다.
        let replacementIDs = stride(from: 0, to: blockCount, by: 3).map {
            BlockID("block-\($0)")
        }
        session.editorModel.replaceSelection(
            .blocks(BlockSelection(blockIDs: replacementIDs))
        )
        _ = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 400))

        // Then: 이전 set을 누적하지 않고 새 identity의 membership 하나로 교체한다.
        #expect(session.blockSelectionMembershipRebuildCount == 2)
        #expect(
            session.blockSelectionMembershipVisitedIDCount
                == selectedIDs.count + replacementIDs.count
        )
        #expect(session.cachedBlockSelectionMembership?.blockIDs.count == replacementIDs.count)

        // When: 다른 exact selection mode로 전환한다.
        session.editorModel.replaceSelection(.caret(blockID: "block-0", offset: 0))
        _ = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 400))

        // Then
        #expect(session.cachedBlockSelectionMembership == nil)
    }

    // MARK: - Support

    private let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

    /// Counts the geometry queries the memoization is supposed to avoid repeating.
    private final class CountingGeometryLayouter: BlockTextLayoutProtocol, @unchecked Sendable {
        private let base = DeterministicBlockTextLayouter()
        private(set) var caretRectCalls = 0
        private(set) var selectionRectCalls = 0

        func measure(_ request: BlockMeasureRequest) -> BlockMeasurement { base.measure(request) }
        func textFrame(for request: BlockMeasureRequest, measuredHeight: Double?) -> EditorRect {
            base.textFrame(for: request, measuredHeight: measuredHeight)
        }
        func lineFragments(for request: BlockMeasureRequest) -> [LineFragmentSnapshot] {
            base.lineFragments(for: request)
        }
        func caretRect(for position: TextPosition, in request: BlockMeasureRequest) -> EditorRect? {
            caretRectCalls += 1
            return base.caretRect(for: position, in: request)
        }
        func selectionRects(for range: TextRange, in request: BlockMeasureRequest) -> [EditorRect] {
            selectionRectCalls += 1
            return base.selectionRects(for: range, in: request)
        }
        func textPosition(at point: EditorPoint, in request: BlockMeasureRequest) -> TextPosition {
            base.textPosition(at: point, in: request)
        }
    }

    private func makeSession(text: String, caretAt offset: Int) -> EditorSession {
        EditorSession(
            blocks: [EditorBlockInput(id: "block", content: BlockContent(text: text))],
            selection: .caret(blockID: "block", offset: offset),
            textLayouter: DeterministicBlockTextLayouter()
        )
    }
}
