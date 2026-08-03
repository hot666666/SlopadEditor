import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 텍스트 선택 네비게이션 입력 이벤트")
struct EditorSessionTextSelectionNavigationInputEventTests {
    @Test("Shift-좌우 입력은 현재 anchor에서 한 글자씩 텍스트 선택을 확장하거나 축소한다")
    func extendsSelectionByCharacter() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hello", id: blockID),
            selection: .caret(blockID: blockID, offset: 3)
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let leftUpdate = try #require(
            session.handleInput(.command(.extendCharacterLeft(viewport: viewport)))
        )
        let rightUpdate = try #require(
            session.handleInput(.command(.extendCharacterRight(viewport: viewport)))
        )

        // Then
        #expect(
            leftUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 3),
                        focus: TextPosition(blockID: blockID, offset: 2)
                    )
                )
        )
        #expect(rightUpdate.selection == .caret(blockID: blockID, offset: 3))
    }

    @Test("Shift-Command-좌우 입력은 현재 anchor에서 블록 텍스트 처음과 끝까지 선택한다")
    func extendsSelectionToTextBoundaries() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hello", id: blockID),
            selection: .caret(blockID: blockID, offset: 3)
        )

        // When
        let startUpdate = try #require(session.handleInput(.command(.extendToTextStart)))
        let endUpdate = try #require(session.handleInput(.command(.extendToTextEnd)))

        // Then
        #expect(
            startUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 3),
                        focus: TextPosition(blockID: blockID, offset: 0)
                    )
                )
        )
        #expect(
            endUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 3),
                        focus: TextPosition(blockID: blockID, offset: 5)
                    )
                )
        )
    }

    @Test("Shift-Option-좌우 입력은 anchor를 유지하고 공백 기준 단어 경계까지 선택한다")
    func extendsSelectionBySpaceDelimitedWordBoundaries() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("alpha beta gamma", id: blockID),
            selection: .caret(blockID: blockID, offset: 8)
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let leftUpdate = try #require(
            session.handleInput(.command(.extendWordLeft(viewport: viewport)))
        )
        let rightUpdate = try #require(
            session.handleInput(.command(.extendWordRight(viewport: viewport)))
        )

        // Then
        #expect(
            leftUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 8),
                        focus: TextPosition(blockID: blockID, offset: 6)
                    )
                )
        )
        #expect(
            rightUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 8),
                        focus: TextPosition(blockID: blockID, offset: 10)
                    )
                )
        )
    }

    @Test("Shift-Option-Left 반복 입력은 선택 focus를 왼쪽 단어 경계로 계속 이동한다")
    func repeatedlyExtendsWordSelectionLeftFromFocus() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("alpha beta gamma", id: blockID),
            selection: .caret(blockID: blockID, offset: 16)
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let firstUpdate = try #require(
            session.handleInput(.command(.extendWordLeft(viewport: viewport)))
        )
        let echoUpdate = try #require(
            session.handleInput(
                .activeTextSelectionChanged(blockID: blockID, selectedRange: TextRange(11, 16))
            )
        )
        let secondUpdate = try #require(
            session.handleInput(.command(.extendWordLeft(viewport: viewport)))
        )

        // Then
        let firstSelection = TextSelection(
            anchor: TextPosition(blockID: blockID, offset: 16),
            focus: TextPosition(blockID: blockID, offset: 11)
        )
        #expect(firstUpdate.selection == .text(firstSelection))
        #expect(echoUpdate.selection == .text(firstSelection))
        #expect(
            secondUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 16),
                        focus: TextPosition(blockID: blockID, offset: 6)
                    )
                )
        )
    }
}
