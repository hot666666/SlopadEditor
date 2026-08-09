import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 활성 텍스트 입력 이벤트")
struct EditorSessionActiveTextInputEventTests {
    @Test("활성 텍스트 선택 변경 이벤트는 런타임 선택 상태를 갱신한다")
    func handlesActiveTextSelectionChangedEvent() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("Hello", id: blockID))

        // When
        let update = try #require(
            session.handleInput(
                .activeTextSelectionChanged(blockID: blockID, selectedRange: TextRange(1, 4))
            )
        )

        // Then
        #expect(
            update.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 1),
                        focus: TextPosition(blockID: blockID, offset: 4)
                    )
                )
        )
        #expect(session.activeTextRange() == TextRange(1, 4))
        #expect(session.activeTextPosition()?.offset == 4)
        #expect(update.invalidation.blockIDs.isEmpty)
        #expect(!update.invalidation.layoutGeometryChanged)
    }

    @Test("활성 텍스트 선택 범위가 canonical 본문 밖이면 선택을 변경하지 않는다")
    func rejectsSelectionOutsideCanonicalText() {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Body", id: blockID),
            selection: .caret(blockID: blockID, offset: 2)
        )

        // When
        let update = session.handleInput(
            .activeTextSelectionChanged(
                blockID: blockID,
                selectedRange: TextRange(0, 5)
            )
        )

        // Then
        #expect(update?.selection == .caret(blockID: blockID, offset: 2))
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 2))
    }

    @Test("렌더링 스냅샷은 활성 텍스트 입력 descriptor를 포함한다")
    func renderSnapshotIncludesActiveTextInputDescriptor() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hello", id: blockID),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 4),
                    focus: TextPosition(blockID: blockID, offset: 1, affinity: .upstream)
                )
            ),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 2)
        )

        // When
        let snapshot = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 400))

        // Then
        #expect(snapshot.activeTextInput?.selectedRange == TextRange(1, 4))
        #expect(snapshot.activeTextInput?.focusOffset == 1)
        #expect(snapshot.activeTextInput?.focusAffinity == .upstream)
    }

    @Test("cross-block 렌더링은 focus 블록 native 입력과 visible fragment를 분리한다")
    func crossBlockRenderSeparatesNativeFocusFromVisiblePresentation() throws {
        // Given
        let a: BlockID = "a"
        let empty: BlockID = "empty"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "abcd")),
                Block(id: empty),
                Block(id: b, content: BlockContent(text: "efgh")),
            ]),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: a, offset: 2),
                    focus: TextPosition(blockID: b, offset: 2, affinity: .upstream)
                )
            ),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 0)
        )

        // When
        let snapshot = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 400))

        // Then
        #expect(snapshot.activeTextInput?.renderDescriptor.measureRequest.blockID == b)
        #expect(snapshot.activeTextInput?.selectedRange == TextRange(0, 2))
        #expect(snapshot.activeTextInput?.focusOffset == 2)
        #expect(snapshot.selectionPresentation.visibleTextSelections.map(\.blockID) == [a, empty, b])
        #expect(snapshot.selectionPresentation.visibleTextSelections.map(\.range) == [
            TextRange(2, 4), TextRange(0, 0), TextRange(0, 2),
        ])
    }

    @Test("긴 cross-block 선택도 현재 viewport의 fragment만 투영한다")
    func crossBlockRenderProjectsOnlyVisibleFragments() {
        // Given
        let inputs = (0..<10_000).map { index in
            EditorBlockInput(id: BlockID("b\(index)"), content: BlockContent(text: "x"))
        }
        let session = EditorSession(
            blocks: inputs,
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: "b0", offset: 0),
                    focus: TextPosition(blockID: "b9999", offset: 1)
                )
            ),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 0)
        )

        // When
        let snapshot = session.render(
            in: EditorViewport(width: 240, scrollY: 500, height: 30)
        )

        // Then
        #expect(snapshot.visibleBlocks.count < 10_000)
        #expect(
            snapshot.selectionPresentation.visibleTextSelections.map(\.blockID)
                == snapshot.visibleBlocks.map(\.id)
        )
    }

    @Test("cross-block 범위의 atomic divider는 글자 rect 대신 block tint로 표시한다")
    func crossBlockRenderTintsAtomicBlocks() throws {
        // Given
        let a: BlockID = "a"
        let divider: BlockID = "divider"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: divider, kind: .divider),
                Block(id: b, content: BlockContent(text: "B")),
            ]),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: a, offset: 0),
                    focus: TextPosition(blockID: b, offset: 1)
                )
            ),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 0)
        )

        // When
        let snapshot = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 100))
        let atomic = try #require(
            snapshot.selectionPresentation.visibleTextSelections.first { $0.blockID == divider }
        )

        // Then
        #expect(atomic.range == TextRange(0, 0))
        #expect(atomic.rects.isEmpty)
        #expect(atomic.blockTintRect != nil)
    }

    @Test("prefix shortcut replacement 후 활성 입력 selection은 제거된 marker 뒤가 아니라 0으로 동기화된다")
    func handlesPrefixShortcutSelectionAfterNativeReplacement() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("", id: blockID))

        // When
        let update = try #require(
            session.handleInput(
                .command(.replaceText(blockID: blockID, range: TextRange.point(0), text: "# "))
            )
        )

        // Then
        #expect(session.document.block(blockID)?.kind == .heading(level: .h1))
        #expect(session.document.block(blockID)?.content.text == "")
        #expect(update.selection == .caret(blockID: blockID, offset: 0))
        #expect(session.activeTextRange() == TextRange.point(0))
    }
}
