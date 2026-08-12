import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 블록 선택")
struct EditorSessionBlockSelectionTests {
    @Test("히트 테스트 결과 블록 범위는 세션이 블록 선택으로 변환한다")
    func handlesBlockSelection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let session = EditorSession(
            document: makeFlatDocument([Block(id: a), Block(id: b), Block(id: c)])
        )

        // When
        let update = session.handleBlockSelection(
            anchor: BlockHitTestResult(blockID: b, region: .dragHandle),
            focus: BlockHitTestResult(blockID: c, region: .dragHandle)
        )

        // Then
        var resolvedSelection: BlockSelection?
        if case .blocks(let blockSelection) = update.selection {
            resolvedSelection = blockSelection
        }
        let blockSelection = try #require(resolvedSelection)
        #expect(blockSelection.blockIDs == [b, c])
        #expect(blockSelection.anchor == b)
        #expect(blockSelection.focus == c)
        #expect(update.invalidation.blockIDs.isEmpty)
        #expect(!update.invalidation.layoutGeometryChanged)
    }
}
