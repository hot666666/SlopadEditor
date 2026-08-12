import SlopadCoreModel
import Testing

@testable import SlopadEditorEngine

@Suite("에디터 세션 클립보드 입력 이벤트")
struct EditorSessionClipboardInputEventTests {
    @Test("텍스트 선택 copy plan은 endpoint 조각과 rebased mark를 typed payload로 만든다")
    func buildsStructuredTextSliceWritePlan() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            blocks: [
                EditorBlockInput(
                    id: a,
                    kind: .heading(level: .h2),
                    content: BlockContent(
                        text: "abcd",
                        marks: [.init(kind: .strong, range: TextRange(1, 4))]
                    )
                ),
                EditorBlockInput(
                    id: b, kind: .todo(isChecked: true), content: BlockContent(text: "efgh")),
            ],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: a, offset: 2),
                    focus: TextPosition(blockID: b, offset: 2)
                )
            ),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let plan = try #require(session.clipboardWritePlan())
        guard case .textSlice(let slice) = plan.payload.content else {
            Issue.record("text slice payload가 필요하다")
            return
        }

        // Then
        #expect(plan.payload.version == EditorClipboardPayload.currentVersion)
        #expect(slice.blocks.map { $0.content.text } == ["cd", "ef"])
        #expect(
            slice.blocks[0].content.marks
                == [BlockContent.InlineMark(kind: .strong, range: TextRange(0, 2))]
        )
        #expect(plan.plainText == "cd\n[x] ef")
    }

    @Test("블록 선택 copy plan은 중복 root를 제거하고 완전한 subtree를 보존한다")
    func buildsStructuredBlockSubtreeWritePlan() throws {
        // Given
        let a: BlockID = "a"
        let child: BlockID = "child"
        var document = makeFlatDocument([
            Block(id: a, kind: .unorderedListItem, content: BlockContent(text: "A"))
        ])
        document.appendChild(Block(id: child, content: BlockContent(text: "Child")), to: a)
        let session = EditorSession(
            document: document,
            selection: .blocks(BlockSelection(blockIDs: [a, child]))
        )

        // When
        let plan = try #require(session.clipboardWritePlan())
        guard case .blockSubtrees(let subtrees) = plan.payload.content else {
            Issue.record("block subtree payload가 필요하다")
            return
        }

        // Then
        #expect(subtrees.blocks.map(\.id) == [a, child])
        #expect(subtrees.blocks.map(\.parentID) == [nil, a])
        #expect(plan.plainText == "• A\nChild")
    }

    @Test("structured paste는 블록 선택을 fresh ID의 완전한 subtree로 한 transaction에 교체한다")
    func structuredPasteReplacesBlockSelectionWithFreshSubtrees() throws {
        // Given
        let destination: BlockID = "destination"
        let tail: BlockID = "tail"
        let source: BlockID = "source"
        let sourceChild: BlockID = "source-child"
        let payload = EditorClipboardPayload(
            content: .blockSubtrees(
                EditorClipboardBlockSubtrees(blocks: [
                    EditorBlockInput(
                        id: source,
                        kind: .heading(level: .h2),
                        content: BlockContent(text: "Title")
                    ),
                    EditorBlockInput(
                        id: sourceChild,
                        parentID: source,
                        kind: .todo(isChecked: true),
                        content: BlockContent(text: "Task")
                    ),
                ])
            )
        )
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: destination, content: BlockContent(text: "Old")),
                Block(id: tail, content: BlockContent(text: "Tail")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [destination]))
        )

        // When
        let update = try #require(
            session.handleInput(.command(.pasteStructured(payload)))
        )
        let insertedRoot = try #require(sessionBlockSelection(update.selection)?.blockIDs.first)
        let insertedChild = try #require(session.document.children(of: insertedRoot).first)

        // Then
        #expect(insertedRoot != source)
        #expect(insertedChild != sourceChild)
        #expect(session.document.rootBlockIDs == [insertedRoot, tail])
        #expect(session.document.block(insertedRoot)?.kind == .heading(level: .h2))
        #expect(session.document.block(insertedChild)?.parentID == insertedRoot)
        #expect(session.document.block(insertedChild)?.content.text == "Task")

        _ = try #require(session.handleInput(.command(.undo)))
        #expect(session.document.rootBlockIDs == [destination, tail])
        #expect(session.document.block(destination)?.content.text == "Old")
    }

    @Test("structured block payload는 텍스트 중간에서 양끝 kind를 버리고 중간 블록만 보존한다")
    func structuredBlockPasteUsesOpenEdgeMergeInsideText() throws {
        // Given
        let destination: BlockID = "destination"
        let first: BlockID = "first"
        let middle: BlockID = "middle"
        let last: BlockID = "last"
        let payload = EditorClipboardPayload(
            content: .blockSubtrees(
                EditorClipboardBlockSubtrees(blocks: [
                    EditorBlockInput(
                        id: first, kind: .heading(level: .h1), content: BlockContent(text: "TITLE")),
                    EditorBlockInput(
                        id: middle, kind: .quote, content: BlockContent(text: "QUOTE")),
                    EditorBlockInput(
                        id: last, kind: .todo(isChecked: false), content: BlockContent(text: "TASK")
                    ),
                ])
            )
        )
        let session = EditorSession(
            document: .singleParagraph("abcdef", id: destination),
            selection: .caret(blockID: destination, offset: 3)
        )

        // When
        let update = try #require(session.handleInput(.command(.pasteStructured(payload))))
        let roots = session.document.rootBlockIDs

        // Then
        #expect(roots.count == 3)
        #expect(roots[0] == destination)
        #expect(session.document.block(roots[0])?.kind == .paragraph)
        #expect(session.document.block(roots[0])?.content.text == "abcTITLE")
        #expect(roots[1] != middle)
        #expect(session.document.block(roots[1])?.kind == .quote)
        #expect(session.document.block(roots[1])?.content.text == "QUOTE")
        #expect(session.document.block(roots[2])?.kind == .paragraph)
        #expect(session.document.block(roots[2])?.content.text == "TASKdef")
        #expect(update.selection == .caret(blockID: roots[2], offset: 4))
    }

    @Test("open-edge structured paste는 DFS 끝이 아니라 root 경계로 자식 subtree를 보존한다")
    func structuredOpenEdgePastePreservesEndpointAndMiddleSubtrees() throws {
        // Given
        let destination: BlockID = "destination"
        let originalChild: BlockID = "original-child"
        let first: BlockID = "first"
        let firstChild: BlockID = "first-child"
        let middle: BlockID = "middle"
        let middleChild: BlockID = "middle-child"
        let last: BlockID = "last"
        let lastChild: BlockID = "last-child"
        let payload = EditorClipboardPayload(
            content: .blockSubtrees(
                EditorClipboardBlockSubtrees(blocks: [
                    EditorBlockInput(
                        id: first, kind: .heading(level: .h1), content: BlockContent(text: "FIRST")),
                    EditorBlockInput(
                        id: firstChild, parentID: first, content: BlockContent(text: "First child")),
                    EditorBlockInput(
                        id: middle, kind: .quote, content: BlockContent(text: "MIDDLE")),
                    EditorBlockInput(
                        id: middleChild, parentID: middle,
                        content: BlockContent(text: "Middle child")),
                    EditorBlockInput(
                        id: last, kind: .todo(isChecked: false), content: BlockContent(text: "LAST")
                    ),
                    EditorBlockInput(
                        id: lastChild, parentID: last, content: BlockContent(text: "Last child")),
                ]))
        )
        var document = Document.singleParagraph("abcdef", id: destination)
        document.appendChild(
            Block(id: originalChild, content: BlockContent(text: "Original child")),
            to: destination
        )
        let session = EditorSession(
            document: document,
            selection: .caret(blockID: destination, offset: 3)
        )

        // When
        let update = try #require(session.handleInput(.command(.pasteStructured(payload))))
        let roots = session.document.rootBlockIDs
        #expect(roots.count == 3)
        let insertedMiddle = try #require(roots.dropFirst().first)
        let trailing = try #require(roots.last)
        let destinationChildren = session.document.children(of: destination)
        let middleChildren = session.document.children(of: insertedMiddle)
        let trailingChildren = session.document.children(of: trailing)

        // Then
        #expect(session.document.block(destination)?.content.text == "abcFIRST")
        #expect(session.document.block(insertedMiddle)?.kind == .quote)
        #expect(session.document.block(trailing)?.content.text == "LASTdef")
        #expect(destinationChildren.count == 1)
        #expect(session.document.block(destinationChildren[0])?.content.text == "First child")
        #expect(middleChildren.count == 1)
        #expect(session.document.block(middleChildren[0])?.content.text == "Middle child")
        #expect(trailingChildren.count == 2)
        #expect(session.document.block(trailingChildren[0])?.content.text == "Last child")
        #expect(trailingChildren[1] == originalChild)
        #expect(update.selection == .caret(blockID: trailing, offset: 4))
    }

    @Test("structured block payload는 caret이 블록 끝이면 wrapper와 subtree를 완전한 새 블록으로 삽입한다")
    func structuredBlockPastePreservesWrappersAtTextBoundary() throws {
        // Given
        let destination: BlockID = "destination"
        let source: BlockID = "source"
        let child: BlockID = "child"
        let payload = EditorClipboardPayload(
            content: .blockSubtrees(
                EditorClipboardBlockSubtrees(blocks: [
                    EditorBlockInput(
                        id: source, kind: .heading(level: .h2), content: BlockContent(text: "Title")
                    ),
                    EditorBlockInput(
                        id: child, parentID: source, kind: .todo(isChecked: false),
                        content: BlockContent(text: "Task")),
                ])
            )
        )
        let session = EditorSession(
            document: .singleParagraph("Body", id: destination),
            selection: .caret(blockID: destination, offset: 4)
        )

        // When
        let update = try #require(session.handleInput(.command(.pasteStructured(payload))))
        let inserted = try #require(sessionBlockSelection(update.selection)?.blockIDs.first)
        let insertedChild = try #require(session.document.children(of: inserted).first)

        // Then
        #expect(session.document.rootBlockIDs == [destination, inserted])
        #expect(session.document.block(destination)?.content.text == "Body")
        #expect(session.document.block(inserted)?.kind == .heading(level: .h2))
        #expect(session.document.block(insertedChild)?.parentID == inserted)
    }

    @Test("structured text slice는 TN을 먼저 병합하고 목적지 양끝에 열린 조각을 흡수한다")
    func structuredTextSliceReplacesCrossBlockSelection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let payload = EditorClipboardPayload(
            content: .textSlice(
                EditorClipboardTextSlice(blocks: [
                    EditorBlockInput(
                        id: "x", kind: .heading(level: .h1), content: BlockContent(text: "X")),
                    EditorBlockInput(
                        id: "y", kind: .todo(isChecked: true), content: BlockContent(text: "Y")),
                ])
            )
        )
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "abcDEF")),
                Block(id: b, content: BlockContent(text: "GHIjkl")),
            ]),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: a, offset: 3),
                    focus: TextPosition(blockID: b, offset: 3)
                )
            )
        )

        // When
        let update = try #require(session.handleInput(.command(.pasteStructured(payload))))
        let roots = session.document.rootBlockIDs

        // Then
        #expect(roots.count == 2)
        #expect(roots[0] == a)
        #expect(session.document.block(roots[0])?.content.text == "abcX")
        #expect(session.document.block(roots[1])?.kind == .paragraph)
        #expect(session.document.block(roots[1])?.content.text == "Yjkl")
        #expect(update.selection == .caret(blockID: roots[1], offset: 1))

        _ = try #require(session.handleInput(.command(.undo)))
        #expect(session.document.rootBlockIDs == [a, b])
        #expect(session.document.block(a)?.content.text == "abcDEF")
        #expect(session.document.block(b)?.content.text == "GHIjkl")
    }

    @Test("텍스트 선택과 블록 선택은 클립보드용 plain text로 노출된다")
    func exposesSelectedPlainText() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "Hello")),
            Block(id: b, content: BlockContent(text: "World")),
        ])
        let textSelectionSession = EditorSession(
            document: document,
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: a, offset: 1),
                    focus: TextPosition(blockID: a, offset: 4)
                )
            )
        )
        let blockSelectionSession = EditorSession(
            document: document,
            selection: .blocks(BlockSelection(blockIDs: [a, b]))
        )
        let crossBlockTextSelectionSession = EditorSession(
            document: document,
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: a, offset: 2),
                    focus: TextPosition(blockID: b, offset: 3)
                )
            )
        )

        // When
        let selectedText = textSelectionSession.selectedPlainText()
        let selectedBlocksText = blockSelectionSession.selectedPlainText()
        let crossBlockText = crossBlockTextSelectionSession.selectedPlainText()

        // Then
        #expect(selectedText == "ell")
        #expect(selectedBlocksText == "Hello\nWorld")
        #expect(crossBlockText == "llo\nWor")
    }

    @Test("native replaceText 콜백은 다중 블록 선택 전체를 한 번에 교체한다")
    func nativeReplacementReplacesCrossBlockSelection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "abcDEF")),
                Block(id: b, content: BlockContent(text: "GHIjkl")),
            ]),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: a, offset: 3),
                    focus: TextPosition(blockID: b, offset: 3)
                )
            )
        )

        // When
        let update = try #require(
            session.handleInput(
                .command(.replaceText(blockID: b, range: TextRange(0, 3), text: "X"))
            )
        )

        // Then
        #expect(session.document.rootBlockIDs == [a])
        #expect(session.document.block(a)?.content.text == "abcXjkl")
        #expect(update.selection == .caret(blockID: a, offset: 4))
    }

    @Test("plain-text paste는 블록 선택을 첫 블록 위치의 paragraph 하나로 교체한다")
    func plainTextPasteReplacesBlockSelection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, kind: .heading(level: .h2), content: BlockContent(text: "B")),
                Block(id: c, content: BlockContent(text: "C")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [b, c]))
        )

        // When
        let update = try #require(session.handleInput(.command(.pasteText("literal # text"))))

        // Then
        #expect(session.document.rootBlockIDs == [a, b])
        #expect(session.document.block(b)?.kind == .paragraph)
        #expect(session.document.block(b)?.content.text == "literal # text")
        #expect(update.selection == .caret(blockID: b, offset: 14))
    }

    @Test("준비된 layout 뒤 블록 선택 plain paste는 survivor의 가시성과 높이를 유지한다")
    func plainTextPasteKeepsSurvivorInPreparedLayout() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, kind: .heading(level: .h2), content: BlockContent(text: "B")),
                Block(id: c, content: BlockContent(text: "C")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [b, c])),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 2)
        )
        let initial = session.render(in: viewport)

        // When
        _ = try #require(session.handleInput(.command(.pasteText("replacement"))))
        let rendered = session.render(in: viewport)
        let revealFrame = session.blockRevealFrame(for: b, viewport: viewport)

        // Then
        #expect(initial.visibleBlocks.map(\.id) == [a, b, c])
        #expect(rendered.visibleBlocks.map(\.id) == [a, b])
        #expect(rendered.visibleBlocks.last?.textRender.measureRequest.text == "replacement")
        #expect(rendered.activeTextInput?.renderDescriptor.measureRequest.blockID == b)
        #expect(rendered.activeTextInput?.selectedRange == TextRange.point(11))
        #expect(rendered.totalHeight == 24)
        #expect(revealFrame?.height == 12)
    }

    @Test("pasteText 명령은 활성 텍스트 선택 범위를 붙여넣은 문자열로 교체한다")
    func pastesTextIntoActiveTextSelection() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hello", id: blockID),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 1),
                    focus: TextPosition(blockID: blockID, offset: 4)
                )
            )
        )

        // When
        let update = try #require(session.handleInput(.command(.pasteText("i"))))

        // Then
        #expect(update.history.canUndo)
        #expect(session.document.block(blockID)?.content.text == "Hio")
        #expect(session.activeTextRange() == TextRange.point(2))
    }

    @Test("pasteText는 여러 블록 텍스트 선택을 앞 prefix와 뒤 suffix 사이에서 교체한다")
    func pastesTextIntoCrossBlockSelection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "abcDEF")),
                Block(id: b, content: BlockContent(text: "GHIjkl")),
            ]),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: a, offset: 3),
                    focus: TextPosition(blockID: b, offset: 3)
                )
            )
        )

        // When
        let update = try #require(session.handleInput(.command(.pasteText("X"))))

        // Then
        #expect(session.document.rootBlockIDs == [a])
        #expect(session.document.block(a)?.content.text == "abcXjkl")
        #expect(update.selection == .caret(blockID: a, offset: 4))
    }

    @Test("cross-block cut은 같은 범위를 한 번에 삭제하고 undo가 역방향 선택을 복원한다")
    func cutsCrossBlockSelectionAndRestoresExactDirection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let selection = TextSelection(
            anchor: TextPosition(blockID: b, offset: 3, affinity: .upstream),
            focus: TextPosition(blockID: a, offset: 3)
        )
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "abcDEF")),
                Block(id: b, content: BlockContent(text: "GHIjkl")),
            ]),
            selection: .text(selection)
        )

        // When
        _ = try #require(session.handleInput(.command(.cutSelection)))
        let undo = try #require(session.handleInput(.command(.undo)))

        // Then
        #expect(session.document.block(a)?.content.text == "abcDEF")
        #expect(session.document.block(b)?.content.text == "GHIjkl")
        #expect(undo.selection == .text(selection))
    }

    @Test("cutSelection 명령은 caret만 있을 때 앞 글자를 지우지 않는다")
    func cutSelectionDoesNotDeleteFromCaret() {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hello", id: blockID),
            selection: .caret(blockID: blockID, offset: 3)
        )

        // When
        let update = session.handleInput(.command(.cutSelection))

        // Then
        #expect(update == nil)
        #expect(session.document.block(blockID)?.content.text == "Hello")
        #expect(session.activeTextRange() == TextRange.point(3))
    }

    @Test("cutSelection 명령은 활성 텍스트 선택 범위를 삭제한다")
    func cutsActiveTextSelection() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hello", id: blockID),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 1),
                    focus: TextPosition(blockID: blockID, offset: 4)
                )
            )
        )

        // When
        let update = try #require(session.handleInput(.command(.cutSelection)))

        // Then
        #expect(update.history.canUndo)
        #expect(session.document.block(blockID)?.content.text == "Ho")
        #expect(session.activeTextRange() == TextRange.point(1))
    }

    @Test("조합 overlay 선택의 복사와 잘라내기는 effective text를 한 transaction으로 처리한다")
    func copiesAndCutsCompositionSelection() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("A🙂B", id: blockID),
            selection: .caret(blockID: blockID, offset: 1)
        )
        _ = session.handleInput(
            .beginComposition(
                blockID: blockID,
                replacementRange: TextRange(1, 2),
                text: "한국어"
            )
        )
        _ = session.handleInput(
            .activeTextSelectionChanged(
                blockID: blockID,
                selectedRange: TextRange(1, 3)
            )
        )

        // When
        let copiedText = session.selectedPlainText()
        let cutUpdate = try #require(session.handleInput(.command(.cutSelection)))
        let textAfterCut = session.document.block(blockID)?.content.text
        let undoUpdate = try #require(session.handleInput(.command(.undo)))

        // Then
        #expect(copiedText == "한국")
        #expect(cutUpdate.selection == .caret(blockID: blockID, offset: 1))
        #expect(textAfterCut == "A어B")
        #expect(session.document.block(blockID)?.content.text == "A🙂B")
        #expect(undoUpdate.selection == .caret(blockID: blockID, offset: 1))
        #expect(!undoUpdate.history.canUndo)
    }

    @Test("undo와 redo 입력 명령은 session history를 통해 문서와 selection을 복원한다")
    func handlesUndoRedoInputCommands() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("", id: blockID))
        _ = try #require(session.handleInput(.command(.insertText("Hi"))))

        // When
        let undoUpdate = try #require(session.handleInput(.command(.undo)))
        let textAfterUndo = session.document.block(blockID)?.content.text
        let redoUpdate = try #require(session.handleInput(.command(.redo)))

        // Then
        #expect(textAfterUndo == "")
        #expect(undoUpdate.selection == .caret(blockID: blockID, offset: 0))
        #expect(!undoUpdate.history.canUndo)
        #expect(undoUpdate.history.canRedo)
        #expect(undoUpdate.invalidation.layoutGeometryChanged)
        #expect(redoUpdate.selection == .caret(blockID: blockID, offset: 2))
        #expect(redoUpdate.history.canUndo)
        #expect(!redoUpdate.history.canRedo)
        #expect(session.document.block(blockID)?.content.text == "Hi")
    }
}
