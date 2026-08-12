import SlopadCoreModel
import Testing

@testable import SlopadEditorEngine

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

    @Test("네이티브 키 입력 경로에도 예약이 적용된다")
    func armedStyleAppliesToNativeReplacement() {
        // Given: AppKit 의 NSTextInputClient 는 글자마다 insertText 가 아니라 replaceText 를
        // 보낸다. 예약이 여기서 빠지면 실제 타이핑에서만 조용히 동작하지 않는다.
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "ab", caretAt: 2)
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))

        // When
        _ = session.handleInput(
            .command(.replaceText(blockID: blockID, range: TextRange.point(2), text: "X")))

        // Then
        #expect(text(session, blockID) == "abX")
        #expect(
            marks(session, blockID) == [
                BlockContent.InlineMark(kind: .strong, range: TextRange(2, 3))
            ])
    }

    @Test("IME 조합을 커밋해도 예약이 적용된다")
    func armedStyleSurvivesCompositionCommit() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "", caretAt: 0)
        _ = session.handleInput(.command(.toggleInlineStyle(.emphasis)))

        // When: 조합 중에는 예약이 걸리지 않지만, 커밋된 텍스트에는 적용되어야 한다.
        _ = session.handleInput(
            .beginComposition(blockID: blockID, replacementRange: TextRange.point(0), text: "ㅎ"))
        _ = session.handleInput(
            .updateComposition(blockID: blockID, replacementRange: TextRange.point(0), text: "한"))
        _ = session.handleInput(.commitComposition)

        // Then
        #expect(text(session, blockID) == "한")
        #expect(
            marks(session, blockID) == [
                BlockContent.InlineMark(kind: .emphasis, range: TextRange(0, 1))
            ])
    }

    @Test("문서를 교체하면 예약이 풀린다")
    func replacingTheDocumentDisarms() throws {
        // Given: 에이전트 패치도 이 경로를 쓴다. 교체된 내용에 이전 예약이 붙으면 안 된다.
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "ab", caretAt: 2)
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))

        // When
        let context = try session.documentContextSnapshot()
        _ = try session.applyDocumentPatch(
            EditorDocumentPatch(
                source: context.source,
                replacementBlocks: [
                    EditorBlockInput(id: blockID, content: BlockContent(text: "zz"))
                ],
                selectionAfter: .caret(blockID: blockID, offset: 2)
            ))
        _ = session.handleInput(.command(.insertText("Y")))

        // Then
        #expect(text(session, blockID) == "zzY")
        #expect(marks(session, blockID).isEmpty)
    }

    @Test("블록 종류가 바뀌면 예약이 풀린다")
    func blockKindConversionDisarms() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "#", caretAt: 1)
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))

        // When: "# " 로 heading 이 되면서 caret 이 블록 시작으로 옮겨진다.
        _ = session.handleInput(.command(.insertText(" ")))
        _ = session.handleInput(.command(.insertText("T")))

        // Then
        #expect(text(session, blockID) == "T")
        #expect(marks(session, blockID).isEmpty)
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
