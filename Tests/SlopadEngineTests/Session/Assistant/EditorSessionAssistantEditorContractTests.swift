import Foundation
import Testing

import SlopadCoreModel
@testable import SlopadEngine

@Suite("AssistantEditorContract 세션 문서 context와 patch")
struct EditorSessionAssistantEditorContractTests {
    @Test("역방향 cross-block 선택은 canonical 순서의 Unicode mark fragment로 투영된다")
    func projectsCrossBlockTextSelection() throws {
        // Given
        let root: BlockID = "root"
        let child: BlockID = "child"
        let tail: BlockID = "tail"
        let rootContent = BlockContent(
            text: "A한글🙂Z",
            marks: [
                BlockContent.InlineMark(kind: .bold, range: TextRange(0, 4)),
                BlockContent.InlineMark(
                    kind: .link(destination: "https://example.com"),
                    range: TextRange(2, 5)
                ),
            ]
        )
        let childContent = BlockContent(
            text: "둘째🚀끝",
            marks: [BlockContent.InlineMark(kind: .italic, range: TextRange(1, 4))]
        )
        let selection = TextSelection(
            anchor: TextPosition(blockID: child, offset: 3),
            focus: TextPosition(blockID: root, offset: 1)
        )
        let session = EditorSession(
            blocks: [
                EditorBlockInput(id: root, kind: .heading(level: .h2), content: rootContent),
                EditorBlockInput(
                    id: child,
                    parentID: root,
                    kind: .todo(isChecked: true),
                    content: childContent
                ),
                EditorBlockInput(id: tail, kind: .quote, content: BlockContent(text: "tail")),
            ],
            selection: .text(selection),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let context = try session.documentContextSnapshot()
        let selectedText = try #require(selectedText(from: context.selectedContent))
        let encodedSelectedContent = try JSONEncoder().encode(context.selectedContent)

        // Then
        #expect(context.document.blocks.map(\.id) == [root, child, tail])
        #expect(context.selection == .text(selection))
        #expect(!encodedSelectedContent.isEmpty)
        #expect(selectedText.fragments.map(\.blockID) == [root, child])
        #expect(selectedText.fragments.map(\.sourceRange) == [TextRange(1, 5), TextRange(0, 3)])
        #expect(selectedText.fragments.map(\.content.text) == ["한글🙂Z", "둘째🚀"])
        #expect(selectedText.fragments[0].parentID == nil)
        #expect(selectedText.fragments[0].kind == .heading(level: .h2))
        #expect(
            selectedText.fragments[0].content.marks
                == [
                    BlockContent.InlineMark(kind: .bold, range: TextRange(0, 3)),
                    BlockContent.InlineMark(
                        kind: .link(destination: "https://example.com"),
                        range: TextRange(1, 4)
                    ),
                ]
        )
        #expect(selectedText.fragments[1].parentID == root)
        #expect(selectedText.fragments[1].kind == .todo(isChecked: true))
        #expect(
            selectedText.fragments[1].content.marks
                == [BlockContent.InlineMark(kind: .italic, range: TextRange(1, 3))]
        )
    }

    @Test("block 선택은 descendant 중복 root를 제거하고 각 subtree를 DFS로 제공한다")
    func projectsSelectedBlockSubtrees() throws {
        // Given
        let root: BlockID = "root"
        let child: BlockID = "child"
        let grandchild: BlockID = "grandchild"
        let sibling: BlockID = "sibling"
        let session = EditorSession(
            blocks: [
                EditorBlockInput(id: root, kind: .heading(level: .h1)),
                EditorBlockInput(id: child, parentID: root, kind: .todo(isChecked: false)),
                EditorBlockInput(id: grandchild, parentID: child, kind: .codeBlock(language: "swift")),
                EditorBlockInput(id: sibling, kind: .quote),
            ],
            selection: .blocks(
                BlockSelection(blockIDs: [grandchild, sibling, child], anchor: grandchild, focus: child)
            ),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let context = try session.documentContextSnapshot()
        let selectedBlocks = try #require(selectedBlocks(from: context.selectedContent))

        // Then
        #expect(selectedBlocks.rootBlockIDs == [child, sibling])
        #expect(selectedBlocks.blocks.map(\.id) == [child, grandchild, sibling])
        #expect(selectedBlocks.blocks.map(\.kind) == [
            .todo(isChecked: false),
            .codeBlock(language: "swift"),
            .quote,
        ])
        #expect(selectedBlocks.blocks.first?.parentID == root)
    }

    @Test("활성 composition 중 context 조회와 patch 적용은 typed error로 거부된다")
    func rejectsActiveComposition() throws {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "AB", offset: 1)
        let context = try session.documentContextSnapshot()
        _ = session.handleInput(
            .beginComposition(
                blockID: blockID,
                replacementRange: .point(1),
                text: "한"
            )
        )
        let patch = EditorDocumentPatch(
            source: context.source,
            replacementBlocks: context.document.blocks,
            selectionAfter: context.selection
        )

        // When
        let queryError = captureError { try session.documentContextSnapshot() }
        let applyError = captureError { try session.applyDocumentPatch(patch) }

        // Then
        #expect(queryError == .activeComposition)
        #expect(applyError == .activeComposition)
        #expect(session.documentSnapshot == context.document)
    }

    @Test("document revision이 바뀐 source는 stale로 거부된다")
    func rejectsStaleRevision() throws {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "A", offset: 1)
        let context = try session.documentContextSnapshot()
        _ = session.handleInput(.command(.insertText("!")))
        let patch = EditorDocumentPatch(
            source: context.source,
            replacementBlocks: [
                EditorBlockInput(id: blockID, content: BlockContent(text: "assistant"))
            ],
            selectionAfter: .caret(blockID: blockID, offset: 9)
        )

        // When
        let error = captureError { try session.applyDocumentPatch(patch) }

        // Then
        #expect(error == .staleSource)
        #expect(session.documentSnapshot.blocks.first?.content.text == "A!")
    }

    @Test("revision이 같아도 selection-only 이동 뒤의 source는 stale로 거부된다")
    func rejectsStaleSelection() throws {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "AB", offset: 0)
        let context = try session.documentContextSnapshot()
        let selectionUpdate = session.handleSelectionChange(.caret(blockID: blockID, offset: 1))
        let patch = EditorDocumentPatch(
            source: context.source,
            replacementBlocks: [
                EditorBlockInput(id: blockID, content: BlockContent(text: "assistant"))
            ],
            selectionAfter: .caret(blockID: blockID, offset: 9)
        )

        // When
        let error = captureError { try session.applyDocumentPatch(patch) }

        // Then
        #expect(selectionUpdate.committedDocumentRevision == nil)
        #expect(session.documentSnapshot.revision.rawValue == 0)
        #expect(error == .staleSource)
    }

    @Test("composite post-image는 insert delete replace reorder를 한 transaction으로 적용한다")
    func appliesCompositePostImageAsOneTransaction() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let d: BlockID = "d"
        let initialBlocks = [
            EditorBlockInput(id: a, content: BlockContent(text: "A")),
            EditorBlockInput(id: b, content: BlockContent(text: "B")),
            EditorBlockInput(id: c, content: BlockContent(text: "C")),
        ]
        let session = EditorSession(
            blocks: initialBlocks,
            selection: .caret(blockID: a, offset: 1),
            textLayouter: DeterministicBlockTextLayouter()
        )
        let context = try session.documentContextSnapshot()
        let replacement = [
            EditorBlockInput(id: c, kind: .heading(level: .h3), content: BlockContent(text: "C replaced")),
            EditorBlockInput(id: d, parentID: c, kind: .todo(isChecked: true), content: BlockContent(text: "new")),
            EditorBlockInput(id: a, kind: .quote, content: BlockContent(text: "A replaced")),
        ]
        let selectionAfter: EditorSelection = .caret(blockID: d, offset: 3)
        let patch = EditorDocumentPatch(
            source: context.source,
            replacementBlocks: replacement,
            selectionAfter: selectionAfter
        )

        // When
        let appliedUpdate = try session.applyDocumentPatch(patch)
        let update = try #require(appliedUpdate)
        let appliedSnapshot = session.documentSnapshot
        let undo = try #require(session.handleInput(.command(.undo)))
        let undoSnapshot = session.documentSnapshot
        let secondUndo = session.handleInput(.command(.undo))
        let redo = try #require(session.handleInput(.command(.redo)))
        let redoSnapshot = session.documentSnapshot

        // Then
        #expect(update.committedDocumentRevision?.rawValue == 1)
        #expect(update.selection == selectionAfter)
        #expect(update.history.canUndo)
        #expect(appliedSnapshot.blocks == replacement)
        #expect(undo.committedDocumentRevision?.rawValue == 2)
        #expect(undoSnapshot.blocks == initialBlocks)
        #expect(secondUndo == nil)
        #expect(redo.committedDocumentRevision?.rawValue == 3)
        #expect(redoSnapshot.blocks == replacement)
        #expect(redo.selection == selectionAfter)
    }

    @Test("invalid post-image는 typed error를 반환하고 document selection history를 보존한다")
    func rejectsInvalidPostImagesWithoutMutation() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let session = makeSession(blockID: a, text: "A", offset: 1)
        let context = try session.documentContextSnapshot()
        var truncatedContent = BlockContent(
            text: "abcd",
            marks: [BlockContent.InlineMark(kind: .bold, range: TextRange(0, 4))]
        )
        truncatedContent.text = "a"
        var overlappingContent = BlockContent(text: "abcd")
        overlappingContent.marks = [
            BlockContent.InlineMark(kind: .bold, range: TextRange(0, 3)),
            BlockContent.InlineMark(kind: .bold, range: TextRange(2, 4)),
        ]
        var unsortedContent = BlockContent(text: "abcd")
        unsortedContent.marks = [
            BlockContent.InlineMark(kind: .italic, range: TextRange(2, 4)),
            BlockContent.InlineMark(kind: .bold, range: TextRange(0, 1)),
        ]
        let invalidCases: [([EditorBlockInput], EditorSelection, EditorDocumentTransactionError)] = [
            ([], .inactive, .emptyDocument),
            (
                [EditorBlockInput(id: a), EditorBlockInput(id: a)],
                .caret(blockID: a, offset: 0),
                .duplicateBlockID(a)
            ),
            (
                [EditorBlockInput(id: a, content: truncatedContent)],
                .caret(blockID: a, offset: 0),
                .invalidContent(blockID: a)
            ),
            (
                [EditorBlockInput(id: a, content: overlappingContent)],
                .caret(blockID: a, offset: 0),
                .invalidContent(blockID: a)
            ),
            (
                [EditorBlockInput(id: a, content: unsortedContent)],
                .caret(blockID: a, offset: 0),
                .invalidContent(blockID: a)
            ),
            (
                [EditorBlockInput(id: a, parentID: b)],
                .caret(blockID: a, offset: 0),
                .missingParent(blockID: a, parentID: b)
            ),
            (
                [EditorBlockInput(id: a, parentID: b), EditorBlockInput(id: b, parentID: a)],
                .caret(blockID: a, offset: 0),
                .cycleDetected(a)
            ),
            (
                [EditorBlockInput(id: a), EditorBlockInput(id: b), EditorBlockInput(id: c, parentID: a)],
                .caret(blockID: a, offset: 0),
                .noncanonicalDepthFirstOrder
            ),
            (
                [EditorBlockInput(id: a, content: BlockContent(text: "A"))],
                .caret(blockID: a, offset: 2),
                .invalidSelection
            ),
        ]

        // When
        let errors = invalidCases.map { blocks, selection, _ in
            captureError {
                try session.applyDocumentPatch(
                    EditorDocumentPatch(
                        source: context.source,
                        replacementBlocks: blocks,
                        selectionAfter: selection
                    )
                )
            }
        }

        // Then
        #expect(errors == invalidCases.map { $0.2 })
        #expect(session.documentSnapshot == context.document)
        #expect(session.editorModel.selection == context.selection)
        #expect(!session.historyState.canUndo)
        #expect(!session.historyState.canRedo)
    }

    @Test("매우 깊은 canonical hierarchy는 stack recursion 없이 한 transaction으로 적용된다")
    func appliesDeepCanonicalHierarchyIteratively() throws {
        // Given
        let depth = 20_000
        let blockIDs = (0..<depth).map { BlockID("deep-\($0)") }
        let replacement = blockIDs.enumerated().map { index, blockID in
            EditorBlockInput(
                id: blockID,
                parentID: index == 0 ? nil : blockIDs[index - 1],
                content: BlockContent(text: "\(index)")
            )
        }
        let session = makeSession(blockID: "original", text: "before", offset: 0)
        let context = try session.documentContextSnapshot()
        let patch = EditorDocumentPatch(
            source: context.source,
            replacementBlocks: replacement,
            selectionAfter: .caret(blockID: blockIDs[depth - 1], offset: 0)
        )

        // When
        let update = try session.applyDocumentPatch(patch)
        let snapshot = session.documentSnapshot

        // Then
        #expect(update?.committedDocumentRevision?.rawValue == 1)
        #expect(snapshot.blocks.count == depth)
        #expect(snapshot.blocks.first?.id == blockIDs[0])
        #expect(snapshot.blocks.last?.id == blockIDs[depth - 1])
        #expect(snapshot.blocks.last?.parentID == blockIDs[depth - 2])
    }

    @Test("매우 긴 parent cycle은 stack trap 없이 typed error로 rollback된다")
    func rejectsDeepCycleIteratively() throws {
        // Given
        let depth = 20_000
        let blockIDs = (0..<depth).map { BlockID("cycle-\($0)") }
        let replacement = blockIDs.enumerated().map { index, blockID in
            EditorBlockInput(
                id: blockID,
                parentID: blockIDs[(index + 1) % depth]
            )
        }
        let session = makeSession(blockID: "original", text: "before", offset: 0)
        let context = try session.documentContextSnapshot()
        let patch = EditorDocumentPatch(
            source: context.source,
            replacementBlocks: replacement,
            selectionAfter: .inactive
        )

        // When
        let error = captureError { try session.applyDocumentPatch(patch) }

        // Then
        #expect(error == .cycleDetected(blockIDs[0]))
        #expect(session.documentSnapshot == context.document)
        #expect(!session.historyState.canUndo)
    }

    @Test("exact no-op patch는 revision update와 history를 만들지 않는다")
    func ignoresExactNoOp() throws {
        // Given
        let blockID: BlockID = "block"
        let session = makeSession(blockID: blockID, text: "same", offset: 2)
        let context = try session.documentContextSnapshot()
        let patch = EditorDocumentPatch(
            source: context.source,
            replacementBlocks: context.document.blocks,
            selectionAfter: context.selection
        )

        // When
        let update = try session.applyDocumentPatch(patch)

        // Then
        #expect(update == nil)
        #expect(session.documentSnapshot.revision.rawValue == 0)
        #expect(!session.historyState.canUndo)
        #expect(!session.historyState.canRedo)
    }
}

private func makeSession(blockID: BlockID, text: String, offset: Int) -> EditorSession {
    EditorSession(
        blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: text))],
        selection: .caret(blockID: blockID, offset: offset),
        textLayouter: DeterministicBlockTextLayouter()
    )
}

private func selectedText(from content: EditorSelectedContent) -> EditorSelectedText? {
    guard case .text(let selectedText) = content else { return nil }
    return selectedText
}

private func selectedBlocks(from content: EditorSelectedContent) -> EditorSelectedBlocks? {
    guard case .blocks(let selectedBlocks) = content else { return nil }
    return selectedBlocks
}

private func captureError<T>(
    _ operation: () throws -> T
) -> EditorDocumentTransactionError? {
    do {
        _ = try operation()
        return nil
    } catch let error as EditorDocumentTransactionError {
        return error
    } catch {
        Issue.record("예상하지 못한 error: \(error)")
        return nil
    }
}
