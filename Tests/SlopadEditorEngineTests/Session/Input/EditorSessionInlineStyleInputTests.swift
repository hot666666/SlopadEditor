import SlopadEditorCoreModel
import Testing

@testable import SlopadEditorEngine

// MARK: - EditorSession InlineStyle Input

@Suite("EditorSession inline style 입력")
struct EditorSessionInlineStyleInputTests {
    @Test("선택 범위에 inline style을 적용한다")
    func appliesStyleToSelectedRange() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "abcd", selecting: TextRange(1, 3))

        // When
        let update = session.handleInput(.command(.toggleInlineStyle(.strong)))

        // Then
        #expect(update != nil)
        #expect(
            marks(session, blockID) == [
                BlockContent.InlineMark(kind: .strong, range: TextRange(1, 3))
            ])
    }

    @Test("같은 style을 다시 적용하면 토글로 해제된다")
    func togglesStyleOffWhenFullyCovered() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "abcd", selecting: TextRange(1, 3))
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))

        // When
        let update = session.handleInput(.command(.toggleInlineStyle(.strong)))

        // Then
        #expect(update != nil)
        #expect(marks(session, blockID).isEmpty)
    }

    @Test("일부만 적용된 범위는 해제가 아니라 완성된다")
    func completesPartiallyStyledRange() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(
            blockID: blockID,
            text: "abcd",
            selecting: TextRange(0, 2),
            marks: [BlockContent.InlineMark(kind: .strong, range: TextRange(0, 1))]
        )

        // When
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))

        // Then
        #expect(
            marks(session, blockID) == [
                BlockContent.InlineMark(kind: .strong, range: TextRange(0, 2))
            ])
    }

    @Test("link 토글은 destination이 달라도 기존 링크를 제거한다")
    func togglingLinkRemovesAnyDestination() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(
            blockID: blockID,
            text: "abcd",
            selecting: TextRange(0, 4),
            marks: [
                BlockContent.InlineMark(kind: .link(destination: "a"), range: TextRange(0, 4))
            ]
        )

        // When
        _ = session.handleInput(.command(.toggleInlineStyle(.link(destination: "b"))))

        // Then
        #expect(marks(session, blockID).isEmpty)
    }

    @Test("clearInlineStyles는 범위의 모든 mark를 제거한다")
    func clearsEveryMarkInRange() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(
            blockID: blockID,
            text: "abcd",
            selecting: TextRange(0, 4),
            marks: [
                BlockContent.InlineMark(kind: .strong, range: TextRange(0, 2)),
                BlockContent.InlineMark(kind: .emphasis, range: TextRange(1, 4)),
                BlockContent.InlineMark(kind: .strikethrough, range: TextRange(2, 4)),
            ]
        )

        // When
        _ = session.handleInput(.command(.clearInlineStyles))

        // Then
        #expect(marks(session, blockID).isEmpty)
    }

    @Test("caret만 있으면 문서를 바꾸지 않고 다음 입력을 위해 예약한다")
    func armsStyleWithoutSelection() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "abcd", selecting: TextRange.point(2))

        // When
        let update = session.handleInput(.command(.toggleInlineStyle(.strong)))

        // Then: 예약은 편집 상태 변화라 update는 나오지만 문서는 그대로다.
        #expect(update != nil)
        #expect(marks(session, blockID).isEmpty)
    }

    @Test("조합 중에는 style 명령을 거부한다")
    func refusesStyleDuringComposition() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "abcd", selecting: TextRange(1, 3))
        _ = session.handleInput(
            .beginComposition(blockID: blockID, replacementRange: TextRange(1, 3), text: "한"))

        // When
        let update = session.handleInput(.command(.toggleInlineStyle(.strong)))

        // Then
        #expect(update == nil)
    }

    @Test("style 적용은 undo 1회로 복원된다")
    func restoresWithSingleUndo() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "abcd", selecting: TextRange(1, 3))
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))
        #expect(marks(session, blockID).count == 1)

        // When
        _ = session.handleInput(.command(.undo))

        // Then
        #expect(marks(session, blockID).isEmpty)
    }

    @Test("한글과 이모지가 섞여도 mark 범위가 grapheme 경계를 지킨다")
    func keepsGraphemeBoundaries() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "한글🙂Z", selecting: TextRange(1, 3))

        // When
        _ = session.handleInput(.command(.toggleInlineStyle(.emphasis)))

        // Then
        let applied = marks(session, blockID)
        #expect(applied == [BlockContent.InlineMark(kind: .emphasis, range: TextRange(1, 3))])
        let block = session.documentSnapshot.blocks.first { $0.id == blockID }
        #expect(block?.content.text == "한글🙂Z")
    }

    @Test("cross-block style은 모든 fragment를 한 transaction으로 토글한다")
    func togglesStyleAcrossTextFragmentsAsOneTransaction() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let selection = TextSelection(
            anchor: TextPosition(blockID: a, offset: 1),
            focus: TextPosition(blockID: b, offset: 2)
        )
        let session = EditorSession(
            blocks: [
                EditorBlockInput(id: a, content: BlockContent(text: "abcd")),
                EditorBlockInput(id: b, content: BlockContent(text: "efgh")),
            ],
            selection: .text(selection),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        _ = try #require(session.handleInput(.command(.toggleInlineStyle(.strong))))

        // Then
        #expect(marks(session, a) == [.init(kind: .strong, range: TextRange(1, 4))])
        #expect(marks(session, b) == [.init(kind: .strong, range: TextRange(0, 2))])
        #expect(session.activeEditorSelection == .text(selection))

        _ = try #require(session.handleInput(.command(.undo)))
        #expect(marks(session, a).isEmpty)
        #expect(marks(session, b).isEmpty)
    }

    // MARK: - Support

    private func makeSession(
        blockID: BlockID,
        text: String,
        selecting range: TextRange,
        marks: [BlockContent.InlineMark] = []
    ) -> EditorSession {
        let anchor = TextPosition(blockID: blockID, offset: range.lowerBound)
        let focus = TextPosition(blockID: blockID, offset: range.upperBound)
        return EditorSession(
            blocks: [
                EditorBlockInput(id: blockID, content: BlockContent(text: text, marks: marks))
            ],
            selection: range.isEmpty
                ? .caret(focus)
                : .text(TextSelection(anchor: anchor, focus: focus)),
            textLayouter: DeterministicBlockTextLayouter()
        )
    }

    private func marks(_ session: EditorSession, _ blockID: BlockID) -> [BlockContent.InlineMark] {
        session.documentSnapshot.blocks.first { $0.id == blockID }?.content.marks ?? []
    }
}
