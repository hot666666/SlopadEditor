import SlopadCoreModel
import Testing

@testable import SlopadEngine

@Suite("에디터 세션 조합 lifecycle 입력 이벤트")
struct EditorSessionCompositionLifecycleInputEventTests {
    @Test("조합 중에는 inline 규칙을 실행하지 않고 확정 때 한 번 적용한다")
    func defersInlineRuleUntilCompositionCommit() throws {
        // Given
        let blockID: BlockID = "inline-composition"
        let session = EditorSession(document: .singleParagraph("", id: blockID))

        // When
        _ = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: blockID,
                    replacementRange: TextRange.point(0),
                    text: "**bold**"
                )
            ))

        // Then
        #expect(session.document.block(blockID)?.content == BlockContent())
        #expect(session.composition?.text == "**bold**")

        // When
        let update = try #require(session.handleInput(.commitComposition))

        // Then
        #expect(
            session.document.block(blockID)?.content
                == BlockContent(
                    text: "bold",
                    marks: [BlockContent.InlineMark(kind: .strong, range: TextRange(0, 4))]
                ))
        #expect(update.selection == .caret(blockID: blockID, offset: 4))
        #expect(session.composition == nil)
    }

    @Test("조합 입력 이벤트는 런타임 활성 입력 상태의 조합으로 반영된다")
    func handlesCompositionInputEvents() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("Hlo", id: blockID))

        // When
        let beginUpdate = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: blockID,
                    replacementRange: TextRange.point(1),
                    text: "el"
                )
            )
        )
        let activeDuringComposition = session.activeTextSelection()
        let commitUpdate = try #require(session.handleInput(.commitComposition))

        // Then
        let composition = try #require(beginUpdate.composition)
        #expect(beginUpdate.composition == composition)
        #expect(composition.compositionRevision == 1)
        #expect(activeDuringComposition?.position.blockID == blockID)
        #expect(activeDuringComposition?.range == TextRange.point(3))
        #expect(commitUpdate.history.canUndo)
        #expect(session.document.block(blockID)?.content.text == "Hello")
        #expect(session.composition == nil)
        #expect(session.activeTextRange() == TextRange.point(3))
    }

    @Test("조합 입력 갱신 후 확정은 최신 replacement 범위를 사용한다")
    func commitsLatestCompositionReplacementRange() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("abcd", id: blockID))
        _ = session.handleInput(
            .beginComposition(
                blockID: blockID,
                replacementRange: TextRange(1, 3),
                text: "X"
            )
        )

        // When
        _ = session.handleInput(
            .updateComposition(
                blockID: blockID,
                replacementRange: TextRange(0, 2),
                text: "Y"
            )
        )
        let update = try #require(session.handleInput(.commitComposition))

        // Then
        #expect(update.history.canUndo)
        #expect(session.document.block(blockID)?.content.text == "Ycd")
        #expect(session.composition == nil)
        #expect(session.activeTextRange() == TextRange.point(1))
    }

    @Test("긴 조합의 유효 선택을 취소하면 canonical 선택을 그대로 복원한다")
    func cancelsCompositionInputEvent() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("Hi", id: blockID))
        _ = session.handleInput(
            .beginComposition(
                blockID: blockID,
                replacementRange: TextRange.point(2),
                text: "긴조합"
            )
        )
        _ = session.handleInput(
            .activeTextSelectionChanged(
                blockID: blockID,
                selectedRange: TextRange.point(4)
            )
        )
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 2))
        #expect(session.activeTextRange() == TextRange.point(4))

        // When
        let update = try #require(session.handleInput(.cancelComposition))

        // Then
        #expect(!update.history.canUndo)
        #expect(update.composition == nil)
        #expect(update.invalidation.blockIDs == Set([blockID]))
        #expect(update.invalidation.layoutGeometryChanged)
        #expect(update.selection == .caret(blockID: blockID, offset: 2))
        #expect(session.document.block(blockID)?.content.text == "Hi")
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 2))
        #expect(session.activeTextRange() == TextRange.point(2))
        #expect(session.composition == nil)
    }

    @Test("TN 위 조합 취소는 원문과 정확한 역방향 선택을 복원한다")
    func crossBlockCompositionCancelRestoresOriginalSelection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let selection = TextSelection(
            anchor: TextPosition(blockID: b, offset: 3, affinity: .upstream),
            focus: TextPosition(blockID: a, offset: 3, affinity: .downstream)
        )
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "abcDEF")),
                Block(id: b, content: BlockContent(text: "GHIjkl")),
            ]),
            selection: .text(selection)
        )
        _ = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: a,
                    replacementRange: TextRange(3, 6),
                    text: "한"
                )))

        // When
        let update = try #require(session.handleInput(.cancelComposition))

        // Then
        #expect(session.document.rootBlockIDs == [a, b])
        #expect(session.document.block(a)?.content.text == "abcDEF")
        #expect(session.document.block(b)?.content.text == "GHIjkl")
        #expect(update.selection == .text(selection))
        #expect(!update.history.canUndo)
    }

    @Test("TN 위 조합 확정은 범위를 한 transaction으로 병합하고 undo가 원선택을 복원한다")
    func crossBlockCompositionCommitReplacesRangeAtomically() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let selection = TextSelection(
            anchor: TextPosition(blockID: b, offset: 3, affinity: .upstream),
            focus: TextPosition(blockID: a, offset: 3, affinity: .downstream)
        )
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "abcDEF")),
                Block(id: b, content: BlockContent(text: "GHIjkl")),
            ]),
            selection: .text(selection)
        )
        _ = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: a,
                    replacementRange: TextRange(3, 6),
                    text: "한"
                )))

        // When
        let commit = try #require(session.handleInput(.commitComposition))

        // Then
        #expect(session.document.rootBlockIDs == [a])
        #expect(session.document.block(a)?.content.text == "abc한jkl")
        #expect(commit.selection == .caret(blockID: a, offset: 4))
        #expect(commit.history.canUndo)

        let undo = try #require(session.handleInput(.command(.undo)))
        #expect(session.document.rootBlockIDs == [a, b])
        #expect(session.document.block(a)?.content.text == "abcDEF")
        #expect(session.document.block(b)?.content.text == "GHIjkl")
        #expect(undo.selection == .text(selection))
    }

    @Test("조합 중 선택 변경 이벤트는 선택 범위와 조합 상태를 함께 유지한다")
    func keepsCompositionDuringSelectionChange() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("Hello", id: blockID))
        let beginUpdate = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: blockID,
                    replacementRange: TextRange(1, 3),
                    text: "i"
                )
            )
        )
        let composition = try #require(beginUpdate.composition)

        // When
        let update = try #require(
            session.handleInput(
                .activeTextSelectionChanged(blockID: blockID, selectedRange: TextRange.point(4))
            )
        )
        let snapshot = session.render(
            in: EditorViewport(width: 240, scrollY: 0, height: 400)
        )

        // Then
        #expect(update.selection == .caret(blockID: blockID, offset: 4))
        #expect(update.composition == composition)
        #expect(snapshot.selection == .caret(blockID: blockID, offset: 4))
        #expect(snapshot.activeTextInput?.selectedRange == TextRange.point(4))
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 5))
        #expect(session.activeTextRange() == TextRange.point(4))
        #expect(session.composition == composition)
    }

    @Test("활성 텍스트 입력 블록이 아닌 조합 갱신은 무시한다")
    func ignoresCompositionUpdateForInactiveBlock() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "B")),
            ])
        )
        _ = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: a,
                    replacementRange: TextRange.point(1),
                    text: "!"
                )
            )
        )

        let composition = session.composition

        // When
        let update = session.handleInput(
            .updateComposition(
                blockID: b,
                replacementRange: TextRange.point(1),
                text: "?"
            )
        )

        // Then
        #expect(update == nil)
        #expect(session.composition == composition)
    }
}
