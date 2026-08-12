import Testing

@testable import SlopadEditorEngine
import SlopadCoreModel

@Suite("에디터 세션 선택 모드 입력 이벤트")
struct EditorSessionSelectionModeInputEventTests {
    @Test("inactive 상태의 텍스트 입력과 조합 입력은 문서를 변경하지 않는다")
    func ignoresTextAndCompositionInputWhenInactive() {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .inactive
        )

        // When
        let textUpdate = session.handleInput(.command(.insertText("!")))
        let compositionUpdate = session.handleInput(
            .beginComposition(blockID: blockID, replacementRange: TextRange.point(1), text: "?")
        )

        // Then
        #expect(textUpdate == nil)
        #expect(compositionUpdate == nil)
        #expect(session.document.block(blockID)?.content.text == "A")
        #expect(session.composition == nil)
        let snapshot = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 400))
        #expect(snapshot.selection == .inactive)
    }

    @Test("블록 선택 상태의 일반 텍스트 입력과 조합 입력은 문서를 변경하지 않는다")
    func ignoresTextAndCompositionInputWhenBlockSelected() {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .blocks(BlockSelection(blockIDs: [blockID]))
        )

        // When
        let textUpdate = session.handleInput(.command(.insertText("!")))
        let compositionUpdate = session.handleInput(
            .beginComposition(blockID: blockID, replacementRange: TextRange.point(1), text: "?")
        )

        // Then
        #expect(textUpdate == nil)
        #expect(compositionUpdate == nil)
        #expect(session.document.block(blockID)?.content.text == "A")
        #expect(session.composition == nil)
        #expect(
            session.render(in: EditorViewport(width: 240, scrollY: 0, height: 400)).selection
                == .blocks(BlockSelection(blockIDs: [blockID]))
        )
    }

    @Test("Escape 입력은 텍스트 편집에서 현재 블록 선택, 블록 선택에서 inactive로 전환한다")
    func handlesEscapeTransitions() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("A", id: blockID))

        // When
        let textUpdate = try #require(session.handleInput(.command(.escape)))
        let blockUpdate = try #require(session.handleInput(.command(.escape)))
        let inactiveUpdate = session.handleInput(.command(.escape))

        // Then
        #expect(textUpdate.selection == .blocks(BlockSelection(blockIDs: [blockID])))
        #expect(blockUpdate.selection == .inactive)
        #expect(inactiveUpdate == nil)
    }

    @Test("cross-block 텍스트 선택의 Escape는 빈 중간 블록까지 구조 선택한다")
    func escapeSelectsEveryTouchedCrossBlock() throws {
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
                    focus: TextPosition(blockID: b, offset: 2)
                )
            )
        )

        // When
        let update = try #require(session.handleInput(.command(.escape)))

        // Then
        #expect(update.selection == .blocks(BlockSelection(blockIDs: [a, empty, b])))
    }

    @Test("clearSelection은 어떤 선택 모드에서든 한 번에 inactive로 간다")
    func clearSelectionDropsAnySelectionInOneStep() throws {
        // Given: escape는 단계별로 올라가므로 호출 횟수가 현재 모드에 의존한다.
        let blockID: BlockID = "a"
        let caretSession = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .caret(blockID: blockID, offset: 1)
        )
        let textSession = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 0),
                    focus: TextPosition(blockID: blockID, offset: 1)
                )
            )
        )
        let blockSession = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .blocks(BlockSelection(blockIDs: [blockID]))
        )

        // When
        let fromCaret = try #require(caretSession.handleInput(.command(.clearSelection)))
        let fromText = try #require(textSession.handleInput(.command(.clearSelection)))
        let fromBlocks = try #require(blockSession.handleInput(.command(.clearSelection)))

        // Then
        #expect(fromCaret.selection == .inactive)
        #expect(fromText.selection == .inactive)
        #expect(fromBlocks.selection == .inactive)
    }

    @Test("이미 inactive면 clearSelection은 소비되지 않는다")
    func clearSelectionIsRefusedWhenAlreadyInactive() {
        // Given
        let session = EditorSession(
            document: .singleParagraph("A", id: "a"),
            selection: .inactive
        )

        // When / Then: escape와 같은 모양으로 호스트에 escalate된다.
        #expect(session.handleInput(.command(.clearSelection)) == nil)
    }

    @Test("조합 중 clearSelection은 조합을 commit한 뒤 해제한다")
    func commitsCompositionBeforeClearingSelection() throws {
        // Given: 조합 중 해제가 마지막 음절을 버리면 안 된다.
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .caret(blockID: blockID, offset: 1)
        )
        _ = session.handleInput(
            .beginComposition(
                blockID: blockID,
                replacementRange: TextRange.point(1),
                text: "!"
            )
        )

        // When
        let update = try #require(session.handleInput(.command(.clearSelection)))

        // Then
        #expect(update.selection == .inactive)
        #expect(session.document.block(blockID)?.content.text == "A!")
        #expect(session.composition == nil)
    }

    @Test("조합 중 Escape는 조합을 commit한 뒤 현재 블록을 선택한다")
    func commitsCompositionBeforeEscapeToBlockSelection() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .caret(blockID: blockID, offset: 1)
        )
        _ = session.handleInput(
            .beginComposition(
                blockID: blockID,
                replacementRange: TextRange.point(1),
                text: "!"
            )
        )

        // When
        let update = try #require(session.handleInput(.command(.escape)))

        // Then
        #expect(update.history.canUndo)
        #expect(session.document.block(blockID)?.content.text == "A!")
        #expect(update.selection == .blocks(BlockSelection(blockIDs: [blockID])))
        #expect(session.composition == nil)
    }

    @Test("inactive 상태의 Enter, 삭제, 들여쓰기, 방향키는 no-op이다")
    func ignoresEditingCommandsWhenInactive() {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .inactive
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let enter = session.handleInput(.command(.enter))
        let delete = session.handleInput(.command(.deleteBackward))
        let indent = session.handleInput(.command(.indent))
        let arrow = session.handleInput(.command(.navigate(.moveDown(viewport: viewport))))

        // Then
        #expect(enter == nil)
        #expect(delete == nil)
        #expect(indent == nil)
        #expect(arrow == nil)
        #expect(session.document.block(blockID)?.content.text == "A")
        #expect(session.render(in: viewport).selection == .inactive)
    }
}
