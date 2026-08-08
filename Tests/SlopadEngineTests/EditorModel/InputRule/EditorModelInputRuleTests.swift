import SlopadCoreModel
import Testing

@testable import SlopadEditorModel

// MARK: - EditorModel InputRules

@Suite("입력 규칙 적용")
struct EditorModelInputRuleTests {
    @Test("prefix 를 완성하면 블록 종류가 바뀌고 마커가 사라진다")
    func convertsOnCompletion() {
        // Given
        let editor = makeEditor(text: "#", caretAt: 1)

        // When
        _ = editor.apply(.insertText(" "))

        // Then
        #expect(editor.document.block("block")?.kind == .heading(level: .h1))
        #expect(editor.document.block("block")?.content.text == "")
        #expect(editor.selection == .caret(blockID: "block", offset: 0))
    }

    @Test("변환은 입력과 같은 트랜잭션이라 undo 1회로 함께 되돌아간다")
    func oneUndoRestoresBoth() {
        // Given: 이것이 확정된 undo 정책이다. 규칙만 취소하는 별도 명령은 두지 않는다 —
        // 블록 변환에서는 사라지는 것이 방금 친 공백뿐이라 체감 차이가 작고, inline 규칙이
        // 들어오는 시점(#31)에 다시 판단한다.
        let editor = makeEditor(text: "#", caretAt: 1)
        _ = editor.apply(.insertText(" "))
        #expect(editor.document.block("block")?.kind == .heading(level: .h1))

        // When
        _ = editor.undo()

        // Then
        #expect(editor.document.block("block")?.kind == .paragraph)
        #expect(editor.document.block("block")?.content.text == "#")
    }

    @Test("code block 안에서는 규칙이 돌지 않는다")
    func skipsCodeBlocks() {
        // Given
        let editor = makeEditor(text: "#", caretAt: 1, kind: .codeBlock(language: nil))

        // When
        _ = editor.apply(.insertText(" "))

        // Then
        #expect(editor.document.block("block")?.kind == .codeBlock(language: nil))
        #expect(editor.document.block("block")?.content.text == "# ")
    }

    @Test("동일한 블록 종류의 prefix 는 리터럴 텍스트로 남는다")
    func sameBlockKindPrefixStaysLiteral() {
        // Given: 이미 H1인 빈 블록에 H1 prefix를 직접 입력한다.
        let editor = makeEditor(text: "#", caretAt: 1, kind: .heading(level: .h1))

        // When
        _ = editor.apply(.insertText(" "))

        // Then: 종류를 바꿀 필요가 없으므로 prefix를 소비하지 않는다.
        #expect(editor.document.block("block")?.kind == .heading(level: .h1))
        #expect(editor.document.block("block")?.content.text == "# ")
        #expect(editor.selection == .caret(blockID: "block", offset: 2))
    }

    @Test("불완전한 문법은 그대로 텍스트로 남는다")
    func leavesIncompleteSyntaxAlone() {
        // Given
        let editor = makeEditor(text: "####", caretAt: 4)

        // When
        _ = editor.apply(.insertText(" "))

        // Then
        #expect(editor.document.block("block")?.kind == .paragraph)
        #expect(editor.document.block("block")?.content.text == "#### ")
    }

    @Test("한글 입력은 규칙을 거치지 않고 그대로 들어간다")
    func hangulPassesThrough() {
        // Given
        let editor = makeEditor(text: "#", caretAt: 1)

        // When
        _ = editor.apply(.insertText("한"))

        // Then
        #expect(editor.document.block("block")?.kind == .paragraph)
        #expect(editor.document.block("block")?.content.text == "#한")
    }

    @Test("규칙이 도중에 실패하면 문서가 변환 이전으로 남는다")
    func rollsBackOnPartialFailure() {
        // Given: 마커 삭제는 되고 종류 변경이 실패하는 상황을 만들 수는 없으므로,
        // 트랜잭션 경계 자체를 확인한다 — 실패한 apply 는 어떤 변경도 남기지 않아야 한다.
        let editor = makeEditor(text: "#", caretAt: 1)
        let before = editor.document

        // When: 존재하지 않는 블록을 겨냥해 실패시킨다.
        let result = editor.apply(
            .replaceText(blockID: "missing", range: TextRange.point(0), text: " "))

        // Then
        #expect(!result.isApplied)
        #expect(editor.document.hasSameCanonicalContent(as: before))
    }

    @Test("네이티브 입력 경로로 들어와도 규칙이 동작한다")
    func worksOnTheNativeReplaceTextPath() {
        // Given: 실제 키보드는 insertText 가 아니라 replaceText 로 들어온다.
        let editor = makeEditor(text: "#", caretAt: 1)

        // When
        _ = editor.apply(
            .replaceText(blockID: "block", range: TextRange.point(1), text: " "))

        // Then
        #expect(editor.document.block("block")?.kind == .heading(level: .h1))
        #expect(editor.document.block("block")?.content.text == "")
    }

    // MARK: - Support

    private func makeEditor(
        text: String, caretAt offset: Int, kind: BlockKind = .paragraph
    ) -> EditorModel {
        EditorModel(
            document: Document(blockInputs: [
                EditorBlockInput(id: "block", kind: kind, content: BlockContent(text: text))
            ]),
            selection: .caret(blockID: "block", offset: offset)
        )
    }
}
