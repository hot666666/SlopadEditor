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
            session.applySlashCommand(.heading1, source: suggestion.source)
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

    @Test("블록 시작이 아닌 slash와 다른 블록 selection 이동은 menu를 dismiss한다")
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
        let otherBlockID: BlockID = "other"
        let fresh = EditorSession(
            document: Document(blockInputs: [
                EditorBlockInput(id: blockID),
                EditorBlockInput(id: otherBlockID, content: BlockContent(text: "other")),
            ]),
            selection: .caret(blockID: blockID, offset: 0)
        )
        _ = fresh.handleInput(
            .command(.replaceText(blockID: blockID, range: .point(0), text: "/"))
        )
        #expect(fresh.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand != nil)

        // When
        let revisionBeforeMove = fresh.documentSnapshot.revision
        let historyBeforeMove = historySnapshot(fresh)
        _ = fresh.handleInput(
            .activeTextSelectionChanged(blockID: otherBlockID, selectedRange: .point(5))
        )

        // Then
        #expect(fresh.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand == nil)
        #expect(fresh.documentSnapshot.revision == revisionBeforeMove)
        #expect(historySnapshot(fresh) == historyBeforeMove)
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

    @Test("같은 revision에서 caret과 query range가 바뀌면 이전 source를 거부한다")
    func staleSelectionAndQueryRangeDismissWithoutMutation() throws {
        // Given
        let blockID: BlockID = "block"
        let session = EditorSession(document: .singleParagraph("", id: blockID))
        _ = session.handleInput(
            .command(.replaceText(blockID: blockID, range: .point(0), text: "/"))
        )
        _ = session.handleInput(
            .command(.replaceText(blockID: blockID, range: .point(1), text: "hea"))
        )
        let staleSource = try #require(
            session.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand
        ).source

        // When: selection changes without advancing the committed document revision.
        _ = session.handleInput(
            .activeTextSelectionChanged(blockID: blockID, selectedRange: .point(3))
        )
        let revisionBeforeApply = session.documentSnapshot.revision
        let historyBeforeApply = historySnapshot(session)
        let currentPresentation = try #require(
            session.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand
        )
        let rejected = session.applySlashCommand(.heading1, source: staleSource)

        // Then
        #expect(currentPresentation.query == "he")
        #expect(currentPresentation.queryRange == TextRange(1, 3))
        #expect(rejected == nil)
        #expect(session.documentSnapshot.revision == revisionBeforeApply)
        #expect(historySnapshot(session) == historyBeforeApply)
        #expect(session.document.block(blockID)?.content.text == "/hea")
        #expect(session.document.block(blockID)?.kind == .paragraph)
        #expect(session.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand == nil)
    }

    @Test("다른 Session의 같은 revision과 query는 이전 epoch source를 거부한다")
    func staleSessionEpochDismissesWithoutMutation() throws {
        // Given
        let blockID: BlockID = "block"
        let original = makeSlashSession(blockID: blockID, query: "hea")
        let staleSource = try #require(
            original.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand
        ).source
        let replacement = makeSlashSession(blockID: blockID, query: "hea")
        let revisionBeforeApply = replacement.documentSnapshot.revision
        let historyBeforeApply = historySnapshot(replacement)

        // When
        let rejected = replacement.applySlashCommand(.heading1, source: staleSource)

        // Then
        #expect(rejected == nil)
        #expect(replacement.documentSnapshot.revision == revisionBeforeApply)
        #expect(historySnapshot(replacement) == historyBeforeApply)
        #expect(replacement.document.block(blockID)?.content.text == "/hea")
        #expect(replacement.document.block(blockID)?.kind == .paragraph)
        #expect(replacement.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand == nil)
    }

    @Test("IME commit 뒤 이전 source는 document와 history를 더 바꾸지 않는다")
    func compositionCommitInvalidatesSource() throws {
        // Given
        let blockID: BlockID = "block"
        let session = makeSlashSession(blockID: blockID, query: "hea")
        let staleSource = try #require(
            session.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand
        ).source

        // When
        _ = session.handleInput(
            .beginComposition(blockID: blockID, replacementRange: .point(4), text: "한")
        )
        _ = session.handleInput(.commitComposition)
        let snapshotAfterCommit = session.documentSnapshot
        let historyAfterCommit = historySnapshot(session)
        let rejected = session.applySlashCommand(.heading1, source: staleSource)

        // Then
        #expect(rejected == nil)
        #expect(session.documentSnapshot == snapshotAfterCommit)
        #expect(historySnapshot(session) == historyAfterCommit)
        #expect(session.document.block(blockID)?.content.text == "/hea한")
        #expect(session.document.block(blockID)?.kind == .paragraph)
        #expect(session.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand == nil)
    }

    @Test("undo와 redo 뒤 이전 source는 추가 mutation 없이 거부된다")
    func undoAndRedoInvalidateSource() throws {
        // Given
        let blockID: BlockID = "block"
        let undoSession = makeSlashSession(blockID: blockID, query: "hea")
        let staleBeforeUndo = try #require(
            undoSession.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand
        ).source

        // When
        _ = undoSession.handleInput(.command(.undo))
        let snapshotAfterUndo = undoSession.documentSnapshot
        let historyAfterUndo = historySnapshot(undoSession)
        let rejectedAfterUndo = undoSession.applySlashCommand(.heading1, source: staleBeforeUndo)

        // Then
        #expect(rejectedAfterUndo == nil)
        #expect(undoSession.documentSnapshot == snapshotAfterUndo)
        #expect(historySnapshot(undoSession) == historyAfterUndo)
        #expect(undoSession.document.block(blockID)?.content.text == "/")
        #expect(undoSession.document.block(blockID)?.kind == .paragraph)

        // Given
        let redoSession = makeSlashSession(blockID: blockID, query: "hea")
        let staleBeforeRedo = try #require(
            redoSession.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand
        ).source

        // When
        _ = redoSession.handleInput(.command(.undo))
        _ = redoSession.handleInput(.command(.redo))
        let snapshotAfterRedo = redoSession.documentSnapshot
        let historyAfterRedo = historySnapshot(redoSession)
        let rejectedAfterRedo = redoSession.applySlashCommand(.heading1, source: staleBeforeRedo)

        // Then
        #expect(rejectedAfterRedo == nil)
        #expect(redoSession.documentSnapshot == snapshotAfterRedo)
        #expect(historySnapshot(redoSession) == historyAfterRedo)
        #expect(redoSession.document.block(blockID)?.content.text == "/hea")
        #expect(redoSession.document.block(blockID)?.kind == .paragraph)
    }

    @Test("외부 patch 뒤 이전 source는 추가 document와 history mutation 없이 거부된다")
    func externalPatchInvalidatesSource() throws {
        // Given
        let blockID: BlockID = "block"
        let session = makeSlashSession(blockID: blockID, query: "hea")
        let staleSource = try #require(
            session.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand
        ).source
        let context = try session.documentContextSnapshot()
        let replacement = [
            EditorBlockInput(
                id: blockID,
                kind: .quote,
                content: BlockContent(text: "external")
            )
        ]

        // When
        _ = try session.applyDocumentPatch(
            EditorDocumentPatch(
                source: context.source,
                replacementBlocks: replacement,
                selectionAfter: .caret(blockID: blockID, offset: 8)
            )
        )
        let snapshotAfterPatch = session.documentSnapshot
        let historyAfterPatch = historySnapshot(session)
        let rejected = session.applySlashCommand(.heading1, source: staleSource)

        // Then
        #expect(rejected == nil)
        #expect(session.documentSnapshot == snapshotAfterPatch)
        #expect(historySnapshot(session) == historyAfterPatch)
        #expect(session.documentSnapshot.blocks == replacement)
        #expect(session.render(in: EditorViewport(width: 400, scrollY: 0, height: 300)).slashCommand == nil)
    }
}

private func makeSlashSession(blockID: BlockID, query: String) -> EditorSession {
    let session = EditorSession(document: .singleParagraph("", id: blockID))
    _ = session.handleInput(
        .command(.replaceText(blockID: blockID, range: .point(0), text: "/"))
    )
    if !query.isEmpty {
        _ = session.handleInput(
            .command(.replaceText(blockID: blockID, range: .point(1), text: query))
        )
    }
    return session
}

private struct SlashHistorySnapshot: Equatable {
    let canUndo: Bool
    let canRedo: Bool
}

private func historySnapshot(_ session: EditorSession) -> SlashHistorySnapshot {
    SlashHistorySnapshot(
        canUndo: session.historyState.canUndo,
        canRedo: session.historyState.canRedo
    )
}
