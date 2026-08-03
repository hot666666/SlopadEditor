import Testing

@testable import SlopadEngine
import SlopadCoreModel
import SlopadEditorModel

@Suite("에디터 세션 canonical document snapshot")
struct EditorSessionDocumentSnapshotTests {
    @Test("content와 구조 mutation은 전체 canonical tree와 단조 revision을 발행한다")
    func projectsCommittedContentAndStructure() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let session = EditorSession(
            blocks: [
                EditorBlockInput(id: a, content: BlockContent(text: "A")),
                EditorBlockInput(id: b, content: BlockContent(text: "B")),
                EditorBlockInput(id: c, content: BlockContent(text: "C")),
            ],
            selection: .caret(blockID: a, offset: 1),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let content = try committedSnapshot(
            from: #require(session.handleInput(.command(.insertText("!")))),
            session: session
        )

        let selectC = session.handleSelectionChange(.blocks(BlockSelection(blockIDs: [c])))
        let parentChange = try committedSnapshot(
            from: #require(session.handleInput(.command(.indent))),
            session: session
        )

        _ = session.handleSelectionChange(.blocks(BlockSelection(blockIDs: [b])))
        let reorder = try committedSnapshot(
            from: session.handleCommand(
                .moveBlockSelection(
                    BlockSelection(blockIDs: [b]),
                    target: BlockDropTarget(blockID: a, placement: .before)
                )
            ),
            session: session
        )

        _ = session.handleSelectionChange(.blocks(BlockSelection(blockIDs: [c])))
        let outdent = try committedSnapshot(
            from: #require(session.handleInput(.command(.outdent))),
            session: session
        )

        _ = session.handleSelectionChange(.caret(blockID: a, offset: 2))
        let insertion = try committedSnapshot(
            from: #require(session.handleInput(.command(.enter))),
            session: session
        )
        let insertedID = try #require(sessionCaretPosition(session.editorModel.selection)?.blockID)

        _ = session.handleSelectionChange(
            .blocks(BlockSelection(blockIDs: [insertedID]))
        )
        let deletion = try committedSnapshot(
            from: #require(session.handleInput(.command(.deleteBackward))),
            session: session
        )

        // Then
        #expect(selectC.committedDocumentRevision == nil)
        #expect(content.revision.rawValue == 1)
        #expect(content.blocks.map(\.id) == [a, b, c])
        #expect(content.blocks.first?.content.text == "A!")

        #expect(parentChange.revision.rawValue == 2)
        #expect(parentChange.blocks.map(\.id) == [a, b, c])
        #expect(parentChange.blocks.first(where: { $0.id == c })?.parentID == b)

        #expect(reorder.revision.rawValue == 3)
        #expect(reorder.blocks.map(\.id) == [b, c, a])
        #expect(reorder.blocks.first(where: { $0.id == c })?.parentID == b)

        #expect(outdent.revision.rawValue == 4)
        #expect(outdent.blocks.map(\.id) == [b, c, a])
        #expect(outdent.blocks.first(where: { $0.id == c })?.parentID == nil)

        #expect(insertion.revision.rawValue == 5)
        #expect(insertion.blocks.map(\.id) == [b, c, a, insertedID])
        #expect(insertion.blocks.first(where: { $0.id == insertedID })?.parentID == nil)

        #expect(deletion.revision.rawValue == 6)
        #expect(deletion.blocks.map(\.id) == [b, c, a])
        #expect(!deletion.blocks.contains(where: { $0.id == insertedID }))
    }

    @Test("초기 getter는 kind mark Unicode와 tree order를 완전하게 round trip한다")
    func roundTripsCompleteInitialProjection() throws {
        // Given
        let root: BlockID = "root"
        let heading: BlockID = "heading"
        let todo: BlockID = "todo"
        let quote: BlockID = "quote"
        let code: BlockID = "code"
        let divider: BlockID = "divider"
        let unordered: BlockID = "unordered"
        let ordered: BlockID = "ordered"
        let markedContent = BlockContent(
            text: "한글🙂link",
            marks: [
                BlockContent.InlineMark(kind: .bold, range: TextRange(0, 2)),
                BlockContent.InlineMark(
                    kind: .link(destination: "https://example.com"),
                    range: TextRange(3, 7)
                ),
            ]
        )
        let inputs = [
            EditorBlockInput(id: root, kind: .paragraph, content: markedContent),
            EditorBlockInput(id: heading, parentID: root, kind: .heading(level: .h2)),
            EditorBlockInput(id: todo, parentID: root, kind: .todo(isChecked: true)),
            EditorBlockInput(id: quote, kind: .quote, content: BlockContent(text: "인용")),
            EditorBlockInput(id: code, kind: .codeBlock(language: "swift")),
            EditorBlockInput(id: divider, kind: .divider),
            EditorBlockInput(id: unordered, kind: .unorderedListItem),
            EditorBlockInput(id: ordered, kind: .orderedListItem(restartNumber: 4)),
        ]
        let session = EditorSession(
            blocks: inputs,
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let snapshot = session.documentSnapshot
        let reconstructed = EditorSession(
            blocks: snapshot.blocks,
            textLayouter: DeterministicBlockTextLayouter()
        ).documentSnapshot

        // Then
        #expect(snapshot.revision.rawValue == 0)
        #expect(snapshot.blocks == inputs)
        #expect(reconstructed.revision.rawValue == 0)
        #expect(reconstructed.blocks == snapshot.blocks)
    }

    @Test("subtree 삭제 snapshot은 모든 descendant를 제거한다")
    func removesDeletedSubtree() throws {
        // Given
        let parent: BlockID = "parent"
        let child: BlockID = "child"
        let grandchild: BlockID = "grandchild"
        let survivor: BlockID = "survivor"
        let session = EditorSession(
            blocks: [
                EditorBlockInput(id: parent),
                EditorBlockInput(id: child, parentID: parent),
                EditorBlockInput(id: grandchild, parentID: child),
                EditorBlockInput(id: survivor),
            ],
            selection: .blocks(BlockSelection(blockIDs: [parent])),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let snapshot = try committedSnapshot(
            from: #require(session.handleInput(.command(.deleteBackward))),
            session: session
        )

        // Then
        #expect(snapshot.revision.rawValue == 1)
        #expect(snapshot.blocks.map(\.id) == [survivor])
    }

    @Test("undo redo와 분기 편집은 이전 canonical revision을 재사용하지 않는다")
    func keepsRevisionMonotonicAcrossHistoryBranches() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            blocks: [EditorBlockInput(id: blockID)],
            selection: .caret(blockID: blockID, offset: 0),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let editA = try committedSnapshot(
            from: #require(session.handleInput(.command(.insertText("A")))),
            session: session
        )
        let undoA = try committedSnapshot(
            from: #require(session.handleInput(.command(.undo))),
            session: session
        )
        let redoA = try committedSnapshot(
            from: #require(session.handleInput(.command(.redo))),
            session: session
        )
        let undoAgain = try committedSnapshot(
            from: #require(session.handleInput(.command(.undo))),
            session: session
        )
        let editB = try committedSnapshot(
            from: #require(session.handleInput(.command(.insertText("B")))),
            session: session
        )

        // Then
        #expect(
            [
                editA.revision.rawValue,
                undoA.revision.rawValue,
                redoA.revision.rawValue,
                undoAgain.revision.rawValue,
                editB.revision.rawValue,
            ]
                == [1, 2, 3, 4, 5]
        )
        #expect(editA.blocks.first?.content.text == "A")
        #expect(undoA.blocks.first?.content.text == "")
        #expect(redoA.blocks.first?.content.text == "A")
        #expect(undoAgain.blocks.first?.content.text == "")
        #expect(editB.blocks.first?.content.text == "B")
        #expect(session.handleInput(.command(.redo)) == nil)
    }

    @Test("canonical 값이 같은 command와 history 이동은 committed revision을 발행하지 않는다")
    func ignoresSemanticNoOps() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    kind: .paragraph,
                    content: BlockContent(text: "A")
                )
            ],
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: DeterministicBlockTextLayouter()
        )
        let baseline = session.documentSnapshot

        // When
        let emptyInsert = session.handleCommand(.insertText(""))
        let sameKind = session.handleCommand(.setBlockKind(blockID: blockID, kind: .paragraph))
        let undo = try #require(session.handleInput(.command(.undo)))

        // Then
        #expect(emptyInsert.committedDocumentRevision == nil)
        #expect(sameKind.committedDocumentRevision == nil)
        #expect(undo.committedDocumentRevision == nil)
        #expect(session.documentSnapshot == baseline)
    }

    @Test("selection layout live composition은 revision을 올리지 않고 commit만 올린다")
    func distinguishesRuntimeUpdatesFromCommittedComposition() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            blocks: [
                EditorBlockInput(id: blockID, content: BlockContent(text: "Hi"))
            ],
            selection: .caret(blockID: blockID, offset: 2),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let selection = try #require(
            session.handleInput(
                .activeTextSelectionChanged(blockID: blockID, selectedRange: .point(1))
            )
        )
        let layout = session.replaceTextLayoutBackend(
            with: DeterministicBlockTextLayouter(lineHeight: 18)
        )
        let begin = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: blockID,
                    replacementRange: .point(1),
                    text: "가"
                )
            )
        )
        let liveSelection = try #require(
            session.handleInput(
                .activeTextSelectionChanged(blockID: blockID, selectedRange: .point(2))
            )
        )
        let update = try #require(
            session.handleInput(
                .updateComposition(
                    blockID: blockID,
                    replacementRange: .point(1),
                    text: "각"
                )
            )
        )
        let committedUpdate = try #require(session.handleInput(.commitComposition))
        let committed = try committedSnapshot(from: committedUpdate, session: session)

        // Then
        #expect(selection.committedDocumentRevision == nil)
        #expect(layout.committedDocumentRevision == nil)
        #expect(begin.committedDocumentRevision == nil)
        #expect(liveSelection.committedDocumentRevision == nil)
        #expect(update.committedDocumentRevision == nil)
        #expect(committed.revision.rawValue == 1)
        #expect(committed.blocks.first?.content.text == "H각i")
        #expect(committedUpdate.composition == nil)
    }

    @Test("live composition 중 다른 block 선택은 commit 한 번과 같은 revision을 발행한다")
    func commitsCompositionOnIncompatibleSelection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            blocks: [
                EditorBlockInput(id: a, content: BlockContent(text: "A")),
                EditorBlockInput(id: b, content: BlockContent(text: "B")),
            ],
            selection: .caret(blockID: a, offset: 1),
            textLayouter: DeterministicBlockTextLayouter()
        )
        let begin = try #require(
            session.handleInput(
                .beginComposition(blockID: a, replacementRange: .point(1), text: "가")
            )
        )

        // When
        let selection = session.handleSelectionChange(.caret(blockID: b, offset: 0))
        let committed = try committedSnapshot(from: selection, session: session)

        // Then
        #expect(begin.committedDocumentRevision == nil)
        #expect(committed.revision.rawValue == 1)
        #expect(committed.blocks.first(where: { $0.id == a })?.content.text == "A가")
        #expect(selection.selection == .caret(blockID: b, offset: 0))
        #expect(selection.composition == nil)
    }

    @Test("full snapshot은 현재 visible range 밖의 canonical block도 포함한다")
    func ignoresViewportProjection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let session = EditorSession(
            blocks: [
                EditorBlockInput(id: a, content: BlockContent(text: "A")),
                EditorBlockInput(id: b, content: BlockContent(text: "B")),
                EditorBlockInput(id: c, content: BlockContent(text: "C")),
            ],
            selection: .caret(blockID: a, offset: 1),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 2)
        )
        let visible = session.render(
            in: EditorViewport(width: 240, scrollY: 0, height: 12)
        )
        _ = session.handleSelectionChange(.caret(blockID: c, offset: 1))

        // When
        let committed = try committedSnapshot(
            from: #require(session.handleInput(.command(.insertText("!")))),
            session: session
        )

        // Then
        #expect(!visible.visibleBlocks.contains(where: { $0.id == c }))
        #expect(committed.blocks.map(\.id) == [a, b, c])
        #expect(committed.blocks.first(where: { $0.id == c })?.content.text == "C!")
    }

    private func committedSnapshot(
        from update: EditorUpdate,
        session: EditorSession
    ) throws -> EditorDocumentSnapshot {
        let revision = try #require(update.committedDocumentRevision)
        let snapshot = session.documentSnapshot
        #expect(snapshot.revision == revision)
        return snapshot
    }
}
