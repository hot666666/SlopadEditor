import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 텍스트 caret 네비게이션 입력 이벤트")
struct EditorSessionTextCaretNavigationInputEventTests {
    @Test("Command-좌우 입력은 텍스트 편집 중 현재 블록 처음과 끝으로 이동한다")
    func movesToTextBoundariesInTextEditing() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hello", id: blockID),
            selection: .caret(blockID: blockID, offset: 3)
        )

        // When
        let startUpdate = try #require(session.handleInput(.command(.moveToTextStart)))
        let endUpdate = try #require(session.handleInput(.command(.moveToTextEnd)))

        // Then
        #expect(startUpdate.selection == .caret(blockID: blockID, offset: 0))
        #expect(endUpdate.selection == .caret(blockID: blockID, offset: 5))
    }

    @Test("Option-좌우 입력은 공백 기준 단어 경계로 이동한다")
    func movesBySpaceDelimitedWordBoundaries() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("alpha beta gamma", id: blockID),
            selection: .caret(blockID: blockID, offset: 8)
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let leftUpdate = try #require(
            session.handleInput(.command(.moveWordLeft(viewport: viewport)))
        )
        let rightUpdate = try #require(
            session.handleInput(.command(.moveWordRight(viewport: viewport)))
        )
        let nextRightUpdate = try #require(
            session.handleInput(.command(.moveWordRight(viewport: viewport)))
        )

        // Then
        #expect(leftUpdate.selection == .caret(blockID: blockID, offset: 6))
        #expect(rightUpdate.selection == .caret(blockID: blockID, offset: 10))
        #expect(nextRightUpdate.selection == .caret(blockID: blockID, offset: 16))
    }
}
