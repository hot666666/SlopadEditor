import Testing

import SlopadCoreModel
import SlopadEditorModel

// EditorModelTextContentCommandTests.swift는 단일 블록 텍스트 삽입/교체/삭제 명령을 검증합니다.
// 마크다운 prefix shortcut은 insertText 후속 처리이므로 별도 테스트 파일에서 검증합니다.
@Suite("EditorModel 텍스트 콘텐츠 명령")
struct EditorModelTextContentCommandTests {
    @Test("캐럿 위치에 텍스트를 삽입하면 블록 텍스트와 캐럿 offset이 갱신된다")
    func givenCaret_whenInsertTextRuns_thenTextIsInsertedAndCaretMoves() {
        // Given
        let blockID: BlockID = "block"
        let editor = EditorModel(
            document: .singleParagraph("AC", id: blockID),
            selection: .caret(blockID: blockID, offset: 1)
        )
        let expectedText = "ABC"
        let expectedSelection = EditorSelection.caret(blockID: blockID, offset: 2)

        // When
        _ = editor.apply(.insertText("B"))

        // Then
        #expect(editor.document.blocks[blockID]?.content.text == expectedText)
        #expect(editor.selection == expectedSelection)
    }

    @Test("단일 블록 텍스트 선택에 텍스트를 삽입하면 선택 범위를 대체한다")
    func givenSingleBlockTextSelection_whenInsertTextRuns_thenSelectedRangeIsReplaced() {
        // Given
        let blockID: BlockID = "block"
        let editor = EditorModel(
            document: .singleParagraph("HelloWorld", id: blockID),
            selection: .text(TextSelection(
                anchor: TextPosition(blockID: blockID, offset: 5),
                focus: TextPosition(blockID: blockID, offset: 10)
            ))
        )
        let expectedText = "Hello Swift"
        let expectedSelection = EditorSelection.caret(blockID: blockID, offset: 11)

        // When
        _ = editor.apply(.insertText(" Swift"))

        // Then
        #expect(editor.document.blocks[blockID]?.content.text == expectedText)
        #expect(editor.selection == expectedSelection)
    }

    @Test("replaceText 명령은 지정 범위를 교체하고 semantic change를 반환한다")
    func givenTextRange_whenReplaceTextRuns_thenRangeIsReplacedAndChangeIsReturned() throws {
        // Given
        let blockID: BlockID = "block"
        let editor = EditorModel(
            document: .singleParagraph("Hlo", id: blockID),
            selection: .caret(blockID: blockID, offset: 0)
        )

        // When
        let result = try #require(
            editor.apply(.replaceText(blockID: blockID, range: TextRange.point(1), text: "el"))
        )
        let change = result.outcome!.change

        // Then
        #expect(editor.document.blocks[blockID]?.content.text == "Hello")
        #expect(editor.selection == .caret(blockID: blockID, offset: 3))
        #expect(change.changedBlockIDs == Set([blockID]))
        #expect(change.operations.isEmpty)
    }

    @Test("여러 블록에 걸친 텍스트 선택에 텍스트 삽입은 unsupported를 반환한다")
    func givenMultiBlockTextSelection_whenInsertTextRuns_thenCommandIsUnsupported() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "B")),
        ])
        let editor = EditorModel(
            document: document,
            selection: .text(TextSelection(
                anchor: TextPosition(blockID: a, offset: 0),
                focus: TextPosition(blockID: b, offset: 1)
            ))
        )
        let expectedRootBlockIDs = [a, b]

        // When
        let result = editor.apply(.insertText("X"))

        // Then
        #expect(result.isApplied == false)
        #expect(editor.document.rootBlockIDs == expectedRootBlockIDs)
        #expect(editor.document.blocks[a]?.content.text == "A")
        #expect(editor.document.blocks[b]?.content.text == "B")
    }

    @Test("deleteText 명령은 지정 범위의 텍스트를 삭제하고 캐럿을 범위 시작으로 이동한다")
    func givenTextRange_whenDeleteTextRuns_thenTextIsDeletedAndCaretMovesToRangeStart() {
        // Given
        let blockID: BlockID = "block"
        let editor = EditorModel(
            document: .singleParagraph("HelloWorld", id: blockID),
            selection: .caret(blockID: blockID, offset: 10)
        )
        let expectedText = "Hello"
        let expectedSelection = EditorSelection.caret(blockID: blockID, offset: 5)

        // When
        _ = editor.apply(.deleteText(blockID: blockID, range: TextRange(5, 10)))

        // Then
        #expect(editor.document.blocks[blockID]?.content.text == expectedText)
        #expect(editor.selection == expectedSelection)
    }

}
