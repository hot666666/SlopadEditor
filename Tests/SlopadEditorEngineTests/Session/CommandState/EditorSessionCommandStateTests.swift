import SlopadCoreModel
import Testing

@testable import SlopadEditorEngine

@Suite("EditorSession command state")
struct EditorSessionCommandStateTests {
    @Test("T1의 전체 선택 범위에서 inline mixed 상태와 block kind를 계산한다")
    func givenPartiallyMarkedT1_whenQueryingCommandState_thenFactsCoverWholeRange() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    kind: .paragraph,
                    content: BlockContent(
                        text: "abcd",
                        marks: [.init(kind: .strong, range: TextRange(0, 2))]
                    )
                )
            ],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 0),
                    focus: TextPosition(blockID: blockID, offset: 4)
                )
            )
        )

        // When
        let state = session.commandState()

        // Then
        #expect(state.detail == .rich)
        #expect(state.toggleState(for: .strong) == .mixed)
        #expect(state.toggleState(for: .emphasis) == .off)
        #expect(state.blockKind == .value(.paragraph))
        #expect(state.availability(for: .toggleInlineStyle(.strong)) == .available)
    }

    @Test("TN inline fact는 모든 text fragment를, block fact는 atomic과 empty를 포함한 span을 본다")
    func givenMixedTN_whenQueryingCommandState_thenInlineAndBlockFactsUseTheirFullSpans() throws {
        // Given
        let a: BlockID = "a"
        let empty: BlockID = "empty"
        let divider: BlockID = "divider"
        let b: BlockID = "b"
        let session = makeSession(
            blocks: [
                EditorBlockInput(
                    id: a,
                    kind: .paragraph,
                    content: BlockContent(
                        text: "abcd",
                        marks: [.init(kind: .strong, range: TextRange(1, 4))]
                    )
                ),
                EditorBlockInput(id: empty, kind: .paragraph),
                EditorBlockInput(id: divider, kind: .divider),
                EditorBlockInput(id: b, kind: .heading(level: .h2), content: .init(text: "efgh")),
            ],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: a, offset: 1),
                    focus: TextPosition(blockID: b, offset: 2)
                )
            )
        )

        // When
        let state = session.commandState()
        let update = try #require(session.apply(.setBlockKind(.quote)))

        // Then
        #expect(state.toggleState(for: .strong) == .mixed)
        #expect(state.blockKind == .mixed)
        #expect(update.committedDocumentRevision != nil)
        #expect(session.documentSnapshot.blocks.map(\.kind) == [.quote, .quote, .quote, .quote])
    }

    @Test("BlockSelection kind는 top-level root만, inline은 선택 root의 text descendant 전체를 본다")
    func givenNestedBlockSelection_whenQueryingAndApplying_thenTargetsStaySeparated() throws {
        // Given
        let root: BlockID = "root"
        let child: BlockID = "child"
        let divider: BlockID = "divider"
        let sibling: BlockID = "sibling"
        let selection = BlockSelection(
            blockIDs: [root, child, sibling],
            anchor: root,
            focus: sibling
        )
        let session = makeSession(
            blocks: [
                EditorBlockInput(id: root, kind: .paragraph, content: .init(text: "R")),
                EditorBlockInput(
                    id: child,
                    parentID: root,
                    kind: .paragraph,
                    content: BlockContent(
                        text: "C",
                        marks: [.init(kind: .strong, range: TextRange(0, 1))]
                    )
                ),
                EditorBlockInput(id: divider, parentID: root, kind: .divider),
                EditorBlockInput(id: sibling, kind: .quote, content: .init(text: "S")),
            ],
            selection: .blocks(selection)
        )

        // When
        let state = session.commandState()
        _ = try #require(session.apply(.toggleInlineStyle(.strong)))
        _ = try #require(session.apply(.setBlockKind(.heading(level: .h1))))

        // Then
        #expect(state.blockKind == .mixed)
        #expect(state.toggleState(for: .strong) == .mixed)
        #expect(marks(in: session, blockID: root) == [.init(kind: .strong, range: TextRange(0, 1))])
        #expect(
            marks(in: session, blockID: child) == [.init(kind: .strong, range: TextRange(0, 1))])
        #expect(
            marks(in: session, blockID: sibling) == [.init(kind: .strong, range: TextRange(0, 1))])
        let kinds = Dictionary(
            uniqueKeysWithValues: session.documentSnapshot.blocks.map { ($0.id, $0.kind) })
        #expect(kinds[root] == .heading(level: .h1))
        #expect(kinds[sibling] == .heading(level: .h1))
        #expect(kinds[child] == .paragraph)
        #expect(kinds[divider] == .divider)
    }

    @Test("empty text와 atomic block은 inline unavailable과 명시적인 block fact를 반환한다")
    func givenEmptyBlockSelectionAndAtomicCaret_whenQuerying_thenResultsAreExplicit() {
        // Given
        let empty: BlockID = "empty"
        let divider: BlockID = "divider"
        let emptySelectionSession = makeSession(
            blocks: [EditorBlockInput(id: empty)],
            selection: .blocks(BlockSelection(blockIDs: [empty]))
        )
        let atomicSession = makeSession(
            blocks: [EditorBlockInput(id: divider, kind: .divider)],
            selection: .caret(blockID: divider, offset: 0)
        )

        // When
        let emptyState = emptySelectionSession.commandState()
        let atomicState = atomicSession.commandState()

        // Then
        #expect(emptyState.toggleState(for: .strong) == .unavailable)
        #expect(emptyState.blockKind == .value(.paragraph))
        #expect(atomicState.toggleState(for: .strong) == .unavailable)
        #expect(atomicState.blockKind == .value(.divider))
        #expect(atomicSession.apply(.toggleInlineStyle(.strong)) == nil)
    }

    @Test("composition query는 commit 필요 availability를 알리고 Session apply는 조합을 바꾸지 않는다")
    func givenComposition_whenQueryingAndApplying_thenCommitBoundaryIsExplicit() throws {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(
            blocks: [EditorBlockInput(id: blockID, content: .init(text: "abcd"))],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 1),
                    focus: TextPosition(blockID: blockID, offset: 3)
                )
            )
        )
        _ = session.handleInput(
            .beginComposition(
                blockID: blockID,
                replacementRange: TextRange(1, 3),
                text: "한"
            )
        )

        // When
        let state = session.commandState()
        let update = session.apply(.toggleInlineStyle(.strong))

        // Then
        #expect(
            state.availability(for: .toggleInlineStyle(.strong)) == .availableAfterCompositionCommit
        )
        #expect(update == nil)
        #expect(try #require(session.composition).text == "한")
        #expect(marks(in: session, blockID: blockID).isEmpty)
    }

    @Test("stable state cache는 scroll에서 재사용되고 selection document composition 변화에서 무효화된다")
    func givenStableCache_whenInputsChange_thenOnlyRelevantIdentityInvalidatesIt() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(
            blocks: [EditorBlockInput(id: blockID, content: .init(text: "abcd"))],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 0),
                    focus: TextPosition(blockID: blockID, offset: 2)
                )
            )
        )
        _ = session.render(in: viewport(scrollY: 0))
        let afterInitial = session.commandStateRichProjectionCount

        // When
        _ = session.render(in: viewport(scrollY: 20))
        let afterScroll = session.commandStateRichProjectionCount
        _ = session.handleInput(
            .activeTextSelectionChanged(blockID: blockID, selectedRange: TextRange(1, 3))
        )
        _ = session.render(in: viewport(scrollY: 20))
        let afterSelection = session.commandStateRichProjectionCount
        _ = session.handleInput(.command(.toggleInlineStyle(.strong)))
        _ = session.render(in: viewport(scrollY: 20))
        let afterDocument = session.commandStateRichProjectionCount
        _ = session.handleInput(
            .beginComposition(blockID: blockID, replacementRange: TextRange(1, 3), text: "ㅎ")
        )
        _ = session.commandState()
        let afterComposition = session.commandStateRichProjectionCount

        // Then
        #expect(afterInitial == 1)
        #expect(afterScroll == afterInitial)
        #expect(afterSelection == afterScroll + 1)
        #expect(afterDocument == afterSelection + 1)
        #expect(afterComposition == afterDocument + 1)
    }

    @Test("live drag command query는 lightweight state만 만들고 full projection을 실행하지 않는다")
    func givenLiveDrag_whenQueryingCommandState_thenFullProjectionCountDoesNotAdvance() {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(
            blocks: [EditorBlockInput(id: blockID, content: .init(text: "abcd"))],
            selection: .caret(blockID: blockID, offset: 0)
        )
        let before = session.commandStateRichProjectionCount
        session.textSelectionDragAnchor = TextPosition(blockID: blockID, offset: 0)

        // When
        let state = session.commandState()

        // Then
        #expect(state.detail == .lightweight)
        #expect(state.toggleState(for: .strong) == .unavailable)
        #expect(session.commandStateRichProjectionCount == before)
    }

    @Test("큰 stable BlockSelection의 scroll query는 O(1) selection identity로 cache를 재사용한다")
    func givenStableBlockSelection_whenScrollingAndQuerying_thenIdentityAndProjectionStayCached() {
        // Given
        let blockIDs = (0..<100).map { BlockID("block-\($0)") }
        let session = makeSession(
            blocks: blockIDs.map {
                EditorBlockInput(id: $0, content: .init(text: "x"))
            },
            selection: .blocks(BlockSelection(blockIDs: blockIDs))
        )
        let selectionIdentity = session.editorModel.selectionIdentity
        _ = session.commandState()
        let initialProjectionCount = session.commandStateRichProjectionCount

        // When
        for frame in 0..<30 {
            _ = session.render(in: viewport(scrollY: Double(frame * 20)))
            _ = session.commandState()
        }

        // Then
        #expect(session.editorModel.selectionIdentity == selectionIdentity)
        #expect(session.commandStateRichProjectionCount == initialProjectionCount)
    }

    @Test("cached caret mark fact는 stored mark toggle과 undo 뒤 각각 갱신된다")
    func givenCachedCaretFact_whenStoredMarkTogglesAndUndoes_thenOffOnOffIsProjected() throws {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(
            blocks: [EditorBlockInput(id: blockID, content: .init(text: "abcd"))],
            selection: .caret(blockID: blockID, offset: 2)
        )
        let initial = session.commandState()

        // When
        _ = try #require(session.apply(.toggleInlineStyle(.strong)))
        let toggled = session.commandState()
        _ = try #require(session.handleInput(.command(.undo)))
        let undone = session.commandState()

        // Then
        #expect(initial.toggleState(for: .strong) == .off)
        #expect(toggled.toggleState(for: .strong) == .on)
        #expect(undone.toggleState(for: .strong) == .off)
    }

    @Test("cached caret mark fact는 clear stored styles 뒤 off로 갱신된다")
    func givenCachedOnCaretFact_whenClearingStoredMarks_thenOffIsProjected() throws {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(
            blocks: [EditorBlockInput(id: blockID, content: .init(text: "abcd"))],
            selection: .caret(blockID: blockID, offset: 2)
        )
        _ = try #require(session.apply(.toggleInlineStyle(.strong)))
        let enabled = session.commandState()

        // When
        _ = try #require(session.apply(.clearInlineStyles))
        let cleared = session.commandState()

        // Then
        #expect(enabled.toggleState(for: .strong) == .on)
        #expect(cleared.toggleState(for: .strong) == .off)
        #expect(cleared.clearInlineStylesAvailability == .unavailable)
    }

    @Test("실제 block reorder drag 중에는 lightweight fact만 제공하고 package action을 거절한다")
    func givenActiveBlockDrag_whenQueryingAndApplying_thenFactsDeferUntilDragEnds() throws {
        // Given
        let a: BlockID = "a"
        let todo: BlockID = "todo"
        let c: BlockID = "c"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            todo: BlockMeasurement(height: 10),
            c: BlockMeasurement(height: 10),
        ]
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: .init(text: "A")),
                Block(id: todo, kind: .todo(isChecked: false), content: .init(text: "T")),
                Block(id: c, content: .init(text: "C")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [todo])),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 100)
        let stable = session.commandState()
        let projectionCount = session.commandStateRichProjectionCount
        _ = try #require(
            session.handleInput(
                .pointer(
                    .beginBlockDrag(
                        documentPoint: EditorPoint(x: 0, y: 15),
                        viewport: viewport
                    )
                )
            )
        )

        // When
        let dragging = session.commandState()
        let kindUpdate = session.apply(.setBlockKind(.quote))
        let todoUpdate = session.toggleTodo(blockID: todo)
        let todoDuringDrag = session.todoState(blockID: todo)
        _ = try #require(
            session.handleInput(
                .pointer(
                    .endBlockDrag(
                        documentPoint: EditorPoint(x: 0, y: 15),
                        viewport: viewport
                    )
                )
            )
        )
        let ended = session.commandState()

        // Then
        #expect(stable.detail == .rich)
        #expect(dragging.detail == .lightweight)
        #expect(session.commandStateRichProjectionCount == projectionCount)
        #expect(kindUpdate == nil)
        #expect(todoUpdate == nil)
        #expect(todoDuringDrag == .unavailable)
        #expect(ended.detail == .rich)
        #expect(ended.blockKind == .value(.todo(isChecked: false)))
        #expect(session.todoState(blockID: todo) == .off)
        #expect(session.document.block(todo)?.kind == .todo(isChecked: false))
    }

    @Test("available query와 apply는 같은 resolver를 사용하고 same-kind no-op도 일치한다")
    func givenStableTarget_whenQueryingAndApplying_thenAvailabilityMatchesApplication() throws {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(
            blocks: [EditorBlockInput(id: blockID, content: .init(text: "abcd"))],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 0),
                    focus: TextPosition(blockID: blockID, offset: 4)
                )
            )
        )
        let state = session.commandState()

        // When
        let inlineUpdate = try #require(session.apply(.toggleInlineStyle(.strong)))
        let nextState = session.commandState()
        let sameKindUpdate = session.apply(.setBlockKind(.paragraph))

        // Then
        #expect(state.availability(for: .toggleInlineStyle(.strong)) == .available)
        #expect(inlineUpdate.committedDocumentRevision != nil)
        #expect(nextState.availability(for: .setBlockKind(.paragraph)) == .unavailable)
        #expect(sameKindUpdate == nil)
    }

    private func makeSession(
        blocks: [EditorBlockInput],
        selection: EditorSelection
    ) -> EditorSession {
        EditorSession(
            blocks: blocks,
            selection: selection,
            textLayouter: DeterministicBlockTextLayouter()
        )
    }

    private func marks(
        in session: EditorSession,
        blockID: BlockID
    ) -> [BlockContent.InlineMark] {
        session.documentSnapshot.blocks.first { $0.id == blockID }?.content.marks ?? []
    }

    private func viewport(scrollY: Double) -> EditorViewport {
        EditorViewport(width: 600, scrollY: scrollY, height: 200)
    }
}
