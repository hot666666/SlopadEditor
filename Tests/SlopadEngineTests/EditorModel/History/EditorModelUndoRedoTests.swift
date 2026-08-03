import Testing

import SlopadCoreModel
@testable import SlopadEditorModel

// EditorModelUndoRedoTests.swift는 undo/redo stack 정책과 snapshot 복원 동작을 검증합니다.
// 개별 command 동작은 기반 블록/텍스트 콘텐츠/키보드 테스트에서 검증하고, 여기서는 snapshot 복원과 stack 예산만 봅니다.
@Suite("EditorModel undo/redo")
struct EditorModelUndoRedoTests {
    @Test("편집 후 실행 취소와 다시 실행을 하면 이전과 이후 snapshot이 복원된다")
    func givenEdit_whenUndoneAndRedone_thenBeforeAndAfterSnapshotsRestore() throws {
        // Given
        let blockID: BlockID = "a"
        let editor = EditorModel(
            document: .singleParagraph("", id: blockID),
            selection: .caret(blockID: blockID, offset: 0)
        )
        let expectedBeforeText = ""
        let expectedAfterText = "Hello"
        let expectedChangedBlockIDs = Set([blockID])

        // When
        let result = editor.apply(.insertText("Hello"))
        let change = try #require(result?.change)
        _ = editor.undo()
        let textAfterUndo = editor.document.blocks[blockID]?.content.text
        _ = editor.redo()
        let textAfterRedo = editor.document.blocks[blockID]?.content.text

        // Then
        #expect(change.changedBlockIDs == expectedChangedBlockIDs)
        #expect(textAfterUndo == expectedBeforeText)
        #expect(textAfterRedo == expectedAfterText)
    }

    @Test("여러 command와 selection 교체를 묶으면 하나의 transaction으로 undo와 redo된다")
    func groupedStepsFormOneTransaction() throws {
        // Given
        let blockID: BlockID = "a"
        let editor = EditorModel(
            document: .singleParagraph("", id: blockID),
            selection: .caret(blockID: blockID, offset: 0)
        )

        // When
        let result = editor.apply([
            .command(.insertText("한글")),
            .replaceSelection(.caret(blockID: blockID, offset: 1)),
            .command(.insertText("!")),
        ])
        let didUndo = editor.undo()
        let textAfterUndo = editor.document.block(blockID)?.content.text
        let selectionAfterUndo = editor.selection
        let didRedo = editor.redo()

        // Then
        #expect(result != nil)
        #expect(didUndo != nil)
        #expect(textAfterUndo == "")
        #expect(selectionAfterUndo == .caret(blockID: blockID, offset: 0))
        #expect(didRedo != nil)
        #expect(editor.document.block(blockID)?.content.text == "한!글")
        #expect(editor.selection == .caret(blockID: blockID, offset: 2))
        #expect(editor.undoStack.count == 1)
    }

    @Test("묶인 command 중 하나가 실패하면 문서와 selection을 transaction 이전으로 되돌린다")
    func groupedStepsRollBackOnAbort() {
        // Given
        let blockID: BlockID = "a"
        let editor = EditorModel(
            document: .singleParagraph("", id: blockID),
            selection: .caret(blockID: blockID, offset: 0)
        )

        // When
        let result = editor.apply([
            .command(.insertText("A")),
            .command(.deleteText(blockID: "missing", range: TextRange(0, 1))),
        ])

        // Then
        #expect(result == nil)
        #expect(editor.document.block(blockID)?.content.text == "")
        #expect(editor.selection == .caret(blockID: blockID, offset: 0))
        #expect(editor.undoStack.isEmpty)
        #expect(editor.redoStack.isEmpty)
    }

    @Test("실행 취소 transaction 개수 제한을 넘으면 가장 오래된 항목이 제거된다")
    func givenUndoBudget_whenTransactionLimitsAreExceeded_thenOldestUndoEntriesAreTrimmed() {
        // Given
        let blockID: BlockID = "a"
        let editor = EditorModel(
            document: .singleParagraph("", id: blockID),
            selection: .caret(blockID: blockID, offset: 0),
            undoConfiguration: EditorUndoConfiguration(
                maxTransactions: 2, maxEstimatedBytes: 32 * 1024 * 1024)
        )
        let expectedUndoStackCount = 2
        let expectedTextAfterFirstUndo = "AB"
        let expectedTextAfterSecondUndo = "A"

        // When
        _ = editor.apply(.insertText("A"))
        _ = editor.apply(.insertText("B"))
        _ = editor.apply(.insertText("C"))
        let undoStackCountAfterInsertions = editor.undoStack.count
        _ = editor.undo()
        let textAfterFirstUndo = editor.document.blocks[blockID]?.content.text
        _ = editor.undo()
        let textAfterSecondUndo = editor.document.blocks[blockID]?.content.text
        let didUndoEvictedTransaction = editor.undo()

        // Then
        #expect(undoStackCountAfterInsertions == expectedUndoStackCount)
        #expect(textAfterFirstUndo == expectedTextAfterFirstUndo)
        #expect(textAfterSecondUndo == expectedTextAfterSecondUndo)
        #expect(didUndoEvictedTransaction == nil)
    }

    @Test("실행 취소 byte 예산을 넘으면 최신 transaction만 보존된다")
    func givenUndoByteBudget_whenEstimatedCostIsExceeded_thenNewestTransactionIsRetained() {
        // Given
        let blockID: BlockID = "a"
        let undoByteBudget = 1
        let editor = EditorModel(
            document: .singleParagraph("", id: blockID),
            selection: .caret(blockID: blockID, offset: 0),
            undoConfiguration: EditorUndoConfiguration(
                maxTransactions: 100, maxEstimatedBytes: undoByteBudget)
        )
        let expectedUndoStackCount = 1
        let expectedTextAfterUndo = "A"

        // When
        _ = editor.apply(.insertText("A"))
        _ = editor.apply(.insertText("B"))
        let undoStackCountAfterInsertions = editor.undoStack.count
        _ = editor.undo()
        let textAfterUndo = editor.document.blocks[blockID]?.content.text
        let didUndoEvictedTransaction = editor.undo()

        // Then
        #expect(undoStackCountAfterInsertions == expectedUndoStackCount)
        #expect(textAfterUndo == expectedTextAfterUndo)
        #expect(didUndoEvictedTransaction == nil)
    }

    @Test("undo 후 새 command를 적용하면 redo stack이 비워진다")
    func givenRedoStack_whenNewCommandIsApplied_thenRedoStackIsCleared() {
        // Given
        let blockID: BlockID = "a"
        let editor = EditorModel(
            document: .singleParagraph("", id: blockID),
            selection: .caret(blockID: blockID, offset: 0)
        )
        let expectedText = "AC"
        let expectedUndoStackCount = 2
        let expectedRedoStackCount = 0

        // When
        _ = editor.apply(.insertText("A"))
        _ = editor.apply(.insertText("B"))
        _ = editor.undo()
        _ = editor.apply(.insertText("C"))

        // Then
        #expect(editor.document.blocks[blockID]?.content.text == expectedText)
        #expect(editor.undoStack.count == expectedUndoStackCount)
        #expect(editor.redoStack.count == expectedRedoStackCount)
    }
}
