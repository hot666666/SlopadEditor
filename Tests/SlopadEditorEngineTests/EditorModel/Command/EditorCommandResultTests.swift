import SlopadCoreModel
import Testing

@testable import SlopadEditorDocumentModel

// MARK: - EditorCommandResult

@Suite("EditorCommandResult 구분")
struct EditorCommandResultTests {
    @Test("적용할 수 없는 명령은 notApplicable을 낸다")
    func reportsNotApplicable() {
        // Given: 존재하지 않는 블록을 겨냥한다.
        let editor = makeEditor(text: "abcd")

        // When
        let result = editor.apply(
            .applyTextStyle(blockID: "missing", range: TextRange(0, 2), style: .strong))

        // Then
        #expect(!result.isApplied)
        #expect(!result.changedDocument)
        #expect(result.outcome == nil)
    }

    @Test("선택만 바뀌면 selectionOnly를 낸다")
    func reportsSelectionOnly() {
        // Given
        let editor = makeEditor(text: "abcd")

        // When: caret 스타일 예약은 편집 상태만 바꾼다.
        let result = editor.apply(.toggleStoredStyle(.strong))

        // Then
        #expect(result.isApplied)
        #expect(!result.changedDocument)
        #expect(result.outcome != nil)
        if case .selectionOnly = result {} else {
            Issue.record("selectionOnly를 기대했지만 \(result)")
        }
    }

    @Test("문서가 바뀌면 document를 낸다")
    func reportsDocumentChange() {
        // Given
        let editor = makeEditor(text: "abcd")

        // When
        let result = editor.apply(.insertText("X"))

        // Then
        #expect(result.isApplied)
        #expect(result.changedDocument)
        #expect(result.outcome?.change.documentChanged == true)
    }

    @Test("빈 명령 목록은 트랜잭션을 만들지 않는다")
    func emptyEntriesDoNothing() {
        // Given
        let editor = makeEditor(text: "abcd")
        let before = editor.historyAvailability

        // When
        let result = editor.apply([])

        // Then
        #expect(!result.isApplied)
        #expect(editor.historyAvailability == before)
    }

    @Test("선택만 바뀐 것과 문서가 바뀐 것을 호출부가 구분할 수 있다")
    func distinguishesPersistenceWorthyChanges() {
        // Given: 이 구분이 없으면 호출부는 캐럿 예약에도 저장을 돌린다.
        let editor = makeEditor(text: "abcd")

        // When
        let armed = editor.apply(.toggleStoredStyle(.strong))
        let typed = editor.apply(.insertText("X"))

        // Then
        #expect(armed.isApplied && !armed.changedDocument)
        #expect(typed.isApplied && typed.changedDocument)
    }

    // MARK: - Support

    private func makeEditor(text: String) -> EditorModel {
        let blockID: BlockID = "block"
        let editor = EditorModel(
            document: Document(blockInputs: [
                EditorBlockInput(id: blockID, content: BlockContent(text: text))
            ]),
            selection: .caret(blockID: blockID, offset: 0)
        )
        return editor
    }
}
