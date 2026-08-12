import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 텍스트 들여쓰기 입력 이벤트")
struct EditorSessionTextIndentInputEventTests {
    @Test("텍스트 편집의 Indent 입력 명령은 현재 줄에 네 칸 들여쓰기를 삽입한다")
    func indentsTextLineInTextEditingMode() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "Parent")),
                Block(id: b, content: BlockContent(text: "Body")),
            ]),
            selection: .caret(blockID: b, offset: 2)
        )

        // When
        let update = try #require(session.handleInput(.command(.indent)))

        // Then
        #expect(session.document.blocks[b]?.parentID == nil)
        #expect(session.document.blocks[b]?.content.text == "    Body")
        #expect(update.selection == .caret(blockID: b, offset: 6))
        #expect(!update.invalidation.visibleSequenceChanged)
        #expect(!update.invalidation.layoutGeometryChanged)
    }

    @Test("텍스트 편집의 Outdent 입력 명령은 현재 줄의 네 칸 들여쓰기를 제거한다")
    func outdentsTextLineInTextEditingMode() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        var document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "Parent")),
            Block(id: c, content: BlockContent(text: "Tail")),
        ])
        document.appendChild(Block(id: b, content: BlockContent(text: "    Body")), to: a)
        let session = EditorSession(
            document: document,
            selection: .caret(blockID: b, offset: 6)
        )

        // When
        let update = try #require(session.handleInput(.command(.outdent)))

        // Then
        #expect(session.document.rootBlockIDs == [a, c])
        #expect(session.document.blocks[b]?.parentID == a)
        #expect(session.document.blocks[b]?.content.text == "Body")
        #expect(update.selection == .caret(blockID: b, offset: 2))
        #expect(!update.invalidation.visibleSequenceChanged)
        #expect(!update.invalidation.layoutGeometryChanged)
    }

    @Test("텍스트 편집의 multi-line 선택 Indent는 선택이 닿은 각 줄에 네 칸을 삽입한다")
    func indentsTouchedLinesInTextSelection() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("a\nb\nc", id: blockID),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 0),
                    focus: TextPosition(blockID: blockID, offset: 3)
                )
            )
        )

        // When
        let update = try #require(session.handleInput(.command(.indent)))

        // Then
        #expect(update.history.canUndo)
        #expect(session.document.block(blockID)?.content.text == "    a\n    b\nc")
    }

    @Test("다중 블록 텍스트 선택의 Indent는 걸친 블록을 구조 이동하고 텍스트 선택을 유지한다")
    func structurallyIndentsCrossBlockTextSelection() throws {
        // Given
        let parent: BlockID = "parent"
        let a: BlockID = "a"
        let b: BlockID = "b"
        let selection = TextSelection(
            anchor: TextPosition(blockID: a, offset: 1),
            focus: TextPosition(blockID: b, offset: 1)
        )
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: parent, content: BlockContent(text: "Parent")),
                Block(id: a, content: BlockContent(text: "AA")),
                Block(id: b, content: BlockContent(text: "BB")),
            ]),
            selection: .text(selection)
        )

        // When
        let update = try #require(session.handleInput(.command(.indent)))

        // Then
        #expect(session.document.block(a)?.parentID == parent)
        #expect(session.document.block(b)?.parentID == parent)
        #expect(update.selection == .text(selection))
        _ = try #require(session.handleInput(.command(.undo)))
        #expect(session.document.rootBlockIDs == [parent, a, b])
        #expect(session.activeEditorSelection == .text(selection))
    }
}
