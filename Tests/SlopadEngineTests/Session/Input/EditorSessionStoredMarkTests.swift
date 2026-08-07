import SlopadCoreModel
import Testing

@testable import SlopadEngine

// MARK: - EditorSession StoredMarks

@Suite("EditorSession caret 상태 스타일 예약")
struct EditorSessionStoredMarkTests {
    @Test("caret에서 예약한 스타일이 다음 입력에 적용된다")
    func armedStyleAppliesToNextInsertion() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "ab", caretAt: 2)

        // When
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))
        _ = session.handleInput(.command(.insertText("X")))

        // Then
        #expect(text(session, blockID) == "abX")
        #expect(
            marks(session, blockID) == [
                BlockContent.InlineMark(kind: .strong, range: TextRange(2, 3))
            ])
    }

    @Test("연속 입력 내내 예약이 유지된다")
    func armedStyleSurvivesContinuedTyping() {
        // Given: 타이핑은 매 글자마다 caret을 옮긴다. 그때마다 예약이 풀리면 첫 글자만 굵어진다.
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "", caretAt: 0)
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))

        // When
        for character in ["a", "b", "c"] {
            _ = session.handleInput(.command(.insertText(character)))
        }

        // Then
        #expect(text(session, blockID) == "abc")
        #expect(
            marks(session, blockID) == [
                BlockContent.InlineMark(kind: .strong, range: TextRange(0, 3))
            ])
    }

    @Test("caret을 옮기면 예약이 풀린다")
    func movingTheCaretDisarms() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "ab", caretAt: 2)
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))

        // When: 사용자가 겨냥한 위치가 바뀌었다.
        _ = session.handleInput(.command(.moveToTextStart))
        _ = session.handleInput(.command(.insertText("X")))

        // Then
        #expect(text(session, blockID) == "Xab")
        #expect(marks(session, blockID).isEmpty)
    }

    @Test("같은 스타일을 두 번 예약하면 해제된다")
    func togglingTwiceDisarms() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "ab", caretAt: 2)

        // When
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))
        _ = session.handleInput(.command(.insertText("X")))

        // Then
        #expect(marks(session, blockID).isEmpty)
    }

    @Test("예약은 문서에 저장되지 않는다")
    func armingDoesNotTouchTheDocument() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "ab", caretAt: 2)
        let before = session.documentSnapshot

        // When
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))

        // Then: 예약은 편집 상태이지 문서 내용이 아니다.
        #expect(session.documentSnapshot.blocks == before.blocks)
    }

    @Test("clearInlineStyles가 caret 예약을 모두 푼다")
    func clearDisarmsEverything() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "ab", caretAt: 2)
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))
        _ = session.handleInput(.command(.toggleInlineStyle(.emphasis)))

        // When
        _ = session.handleInput(.command(.clearInlineStyles))
        _ = session.handleInput(.command(.insertText("X")))

        // Then
        #expect(marks(session, blockID).isEmpty)
    }

    @Test("undo가 예약 상태까지 되돌린다")
    func undoRestoresTheArmedState() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "ab", caretAt: 2)
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))
        _ = session.handleInput(.command(.insertText("X")))
        #expect(marks(session, blockID).count == 1)

        // When: 삽입만 되돌린다. 예약은 삽입 이전 상태로 복원되어야 한다.
        _ = session.handleInput(.command(.undo))
        _ = session.handleInput(.command(.insertText("Y")))

        // Then
        #expect(text(session, blockID) == "abY")
        #expect(
            marks(session, blockID) == [
                BlockContent.InlineMark(kind: .strong, range: TextRange(2, 3))
            ])
    }

    @Test("여러 스타일을 함께 예약할 수 있다")
    func armsSeveralStyles() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "", caretAt: 0)

        // When
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))
        _ = session.handleInput(.command(.toggleInlineStyle(.emphasis)))
        _ = session.handleInput(.command(.insertText("a")))

        // Then
        #expect(
            marks(session, blockID) == [
                BlockContent.InlineMark(kind: .emphasis, range: TextRange(0, 1)),
                BlockContent.InlineMark(kind: .strong, range: TextRange(0, 1)),
            ])
    }

    // MARK: - Support

    private func makeSession(blockID: BlockID, text: String, caretAt offset: Int) -> EditorSession {
        EditorSession(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: text))],
            selection: .caret(blockID: blockID, offset: offset),
            textLayouter: DeterministicBlockTextLayouter()
        )
    }

    private func marks(_ session: EditorSession, _ blockID: BlockID) -> [BlockContent.InlineMark] {
        session.documentSnapshot.blocks.first { $0.id == blockID }?.content.marks ?? []
    }

    private func text(_ session: EditorSession, _ blockID: BlockID) -> String {
        session.documentSnapshot.blocks.first { $0.id == blockID }?.content.text ?? ""
    }
}
