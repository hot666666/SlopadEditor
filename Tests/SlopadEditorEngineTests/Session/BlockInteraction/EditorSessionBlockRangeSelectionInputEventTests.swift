import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 블록 range 선택 입력 이벤트")
struct EditorSessionBlockRangeSelectionInputEventTests {
    @Test("Shift-click block range 이벤트는 anchor부터 focus까지 visible range를 선택한다")
    func selectsVisibleRangeFromPointerRangeEvent() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let session = EditorSession(
            document: makeFlatDocument([Block(id: a), Block(id: b), Block(id: c)])
        )

        // When
        let update = try #require(
            session.handleInput(
                .pointer(
                    .selectBlockRange(
                        anchor: BlockHitTestResult(blockID: a, region: .gutter),
                        focus: BlockHitTestResult(blockID: c, region: .gutter)
                    )
                )
            )
        )

        // Then
        let selection = try #require(sessionBlockSelection(update.selection))
        #expect(selection.blockIDs == [a, b, c])
        #expect(selection.anchor == a)
        #expect(selection.focus == c)
    }
}
