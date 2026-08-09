import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 Enter 입력 이벤트")
struct EditorSessionEnterInputEventTests {
    @Test("Enter 입력 명령은 블록을 나누고 새 블록 활성 입력 상태를 반환한다")
    func handlesEnterSplitBoundaryCommand() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("HelloWorld", id: blockID),
            selection: .caret(blockID: blockID, offset: 5)
        )

        // When
        let update = try #require(session.handleInput(.command(.enter)))

        // Then
        let createdID = try #require(sessionCaretPosition(update.selection)?.blockID)
        #expect(session.document.block(blockID)?.content.text == "Hello")
        #expect(session.document.block(createdID)?.content.text == "World")
        #expect(update.selection == .caret(blockID: createdID, offset: 0))
        #expect(update.invalidation.visibleSequenceChanged)
        #expect(update.invalidation.layoutGeometryChanged)
    }

    @Test("단일 블록 텍스트 선택에서 Enter는 선택을 지우고 두 블록으로 나눈다")
    func replacesSingleBlockTextSelectionWithSplit() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hello selected World", id: blockID),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 6),
                    focus: TextPosition(blockID: blockID, offset: 14)
                )
            )
        )

        // When
        let update = try #require(session.handleInput(.command(.enter)))

        // Then
        let createdID = try #require(sessionCaretPosition(update.selection)?.blockID)
        #expect(session.document.block(blockID)?.content.text == "Hello ")
        #expect(session.document.block(createdID)?.content.text == " World")
        #expect(update.selection == .caret(blockID: createdID, offset: 0))
        #expect(update.invalidation.visibleSequenceChanged)
        #expect(update.invalidation.layoutGeometryChanged)
    }

    @Test("여러 블록 텍스트 선택에서 Enter는 범위를 병합 삭제한 뒤 생존 블록을 나눈다")
    func replacesCrossBlockTextSelectionWithSplit() throws {
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
        let update = try #require(session.handleInput(.command(.enter)))

        // Then
        let createdID = try #require(sessionCaretPosition(update.selection)?.blockID)
        #expect(session.document.rootBlockIDs == [a, createdID])
        #expect(session.document.block(a)?.content.text == "abc")
        #expect(session.document.block(createdID)?.content.text == "jkl")
        #expect(update.selection == .caret(blockID: createdID, offset: 0))
    }

    @Test("블록 선택의 Shift-Enter는 선택과 문서를 유지한다")
    func shiftEnterIsNoOpFromBlockSelection() {
        // Given
        let a: BlockID = "a"
        let selection = EditorSelection.blocks(BlockSelection(blockIDs: [a]))
        let session = EditorSession(
            document: .singleParagraph("Alpha", id: a),
            selection: selection
        )

        // When
        let update = session.handleInput(.command(.shiftEnter))

        // Then
        #expect(update == nil)
        #expect(session.document.block(a)?.content.text == "Alpha")
        #expect(session.activeEditorSelection == selection)
    }

    @Test("블록 선택에서 Enter는 첫 번째 선택 블록 끝을 텍스트 편집으로 전환한다")
    func entersTextEditingFromBlockSelection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "Alpha")),
                Block(id: b, content: BlockContent(text: "Beta")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [a, b]))
        )

        // When
        let update = try #require(session.handleInput(.command(.enter)))

        // Then
        #expect(update.selection == .caret(blockID: a, offset: 5))
    }
}
