import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 슬래시 명령 런타임")
struct EditorSessionSlashCommandTests {
    @Test("실제 선행 슬래시 입력은 query를 투영하고 한 transaction으로 변환한다")
    func typedSlashStartsQueryAndUndoRestoresIt() throws {
        // Given
        let blockID: BlockID = "block"
        let session = EditorSession(document: .singleParagraph("", id: blockID))

        // When
        let slashUpdate = try #require(
            session.handleInput(.command(.replaceText(blockID: blockID, range: .point(0), text: "/")))
        )
        _ = session.handleInput(
            .command(.replaceText(blockID: blockID, range: .point(1), text: "hea"))
        )
        let suggestion = try #require(
            session.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand
        )

        // Then
        #expect(slashUpdate.committedDocumentRevision != nil)
        #expect(suggestion.query == "hea")
        #expect(suggestion.triggerRange == TextRange(0, 1))
        #expect(suggestion.queryRange == TextRange(1, 4))
        #expect(suggestion.commands.contains(.heading1))

        // When
        let apply = try #require(
            session.applySlashCommand(.heading1, sourceRevision: suggestion.sourceRevision)
        )

        // Then
        #expect(apply.history.canUndo)
        #expect(session.document.block(blockID)?.content.text == "")
        #expect(session.document.block(blockID)?.kind == .heading(level: .h1))

        // When
        _ = session.handleInput(.command(.undo))

        // Then
        #expect(session.document.block(blockID)?.content.text == "/hea")
        #expect(session.document.block(blockID)?.kind == .paragraph)
    }

    @Test("기존 slash text와 paste는 menu를 열지 않는다")
    func existingTextAndPasteDoNotStartQuery() {
        // Given
        let existingID: BlockID = "existing"
        let existing = EditorSession(
            document: .singleParagraph("/heading", id: existingID),
            selection: .caret(blockID: existingID, offset: 8)
        )
        let pastedID: BlockID = "pasted"
        let pasted = EditorSession(document: .singleParagraph("", id: pastedID))

        // When
        _ = pasted.handleInput(.command(.pasteText("/heading")))

        // Then
        #expect(existing.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand == nil)
        #expect(pasted.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand == nil)
    }

    @Test("블록 시작이 아닌 slash와 selection 이동은 menu를 dismiss한다")
    func invalidContextAndSelectionDismiss() throws {
        // Given
        let blockID: BlockID = "block"
        let session = EditorSession(document: .singleParagraph("text", id: blockID))

        // When
        _ = session.handleInput(
            .command(.replaceText(blockID: blockID, range: .point(4), text: "/"))
        )

        // Then
        #expect(session.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand == nil)

        // Given
        let fresh = EditorSession(document: .singleParagraph("", id: blockID))
        _ = fresh.handleInput(
            .command(.replaceText(blockID: blockID, range: .point(0), text: "/"))
        )
        #expect(fresh.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand != nil)

        // When
        _ = fresh.handleInput(.activeTextSelectionChanged(blockID: blockID, selectedRange: .point(0)))

        // Then
        #expect(fresh.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand == nil)
    }

    @Test("runtime dismiss는 canonical revision이나 undo history를 만들지 않는다")
    func runtimeDismissIsNotCanonicalMutation() throws {
        // Given
        let blockID: BlockID = "block"
        let session = EditorSession(document: .singleParagraph("", id: blockID))
        _ = session.handleInput(
            .command(.replaceText(blockID: blockID, range: .point(0), text: "/"))
        )
        let revisionBeforeDismiss = session.documentSnapshot.revision

        // When
        session.dismissSlashCommand()

        // Then
        #expect(session.documentSnapshot.revision == revisionBeforeDismiss)
        #expect(session.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand == nil)

        // When: the only undo is still the slash text insertion.
        _ = session.handleInput(.command(.undo))

        // Then
        #expect(session.document.block(blockID)?.content.text == "")
    }

    @Test("IME 조합은 menu를 숨기고 stale revision 선택은 거부한다")
    func compositionAndStaleRevisionDismiss() throws {
        // Given
        let blockID: BlockID = "block"
        let session = EditorSession(document: .singleParagraph("", id: blockID))
        _ = session.handleInput(
            .command(.replaceText(blockID: blockID, range: .point(0), text: "/"))
        )
        let source = try #require(
            session.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand
        ).sourceRevision

        // When: the query advances the canonical revision.
        _ = session.handleInput(
            .command(.replaceText(blockID: blockID, range: .point(1), text: "h"))
        )

        // Then
        #expect(session.applySlashCommand(.heading1, sourceRevision: source) == nil)

        // Given: a fresh typed trigger starts a new runtime.
        let composing = EditorSession(document: .singleParagraph("", id: blockID))
        _ = composing.handleInput(
            .command(.replaceText(blockID: blockID, range: .point(0), text: "/"))
        )

        // When
        _ = composing.handleInput(
            .beginComposition(blockID: blockID, replacementRange: .point(1), text: "한")
        )

        // Then
        #expect(composing.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand == nil)

        // When
        _ = composing.handleInput(.commitComposition)

        // Then: composition dismisses the runtime; it does not infer a new trigger from text.
        #expect(composing.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand == nil)
    }
}
