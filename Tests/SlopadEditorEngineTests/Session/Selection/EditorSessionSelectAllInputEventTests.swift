import Testing

@testable import SlopadEditorEngine
import SlopadCoreModel

@Suite("에디터 세션 전체 선택 입력 이벤트")
struct EditorSessionSelectAllInputEventTests {
    @Test("Cmd-A는 텍스트 편집 중 현재 블록 텍스트 전체를 먼저 선택한 뒤 전체 visible block으로 확장한다")
    func escalatesSelectAllFromTextToVisibleBlocks() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "Hello")),
                Block(id: b, content: BlockContent(text: "World")),
            ]),
            selection: .caret(blockID: a, offset: 2)
        )

        // When
        let textUpdate = try #require(session.handleInput(.command(.selectAll)))
        let blockUpdate = try #require(session.handleInput(.command(.selectAll)))

        // Then
        #expect(
            textUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: a, offset: 0),
                        focus: TextPosition(blockID: a, offset: 5)
                    )
                )
        )
        let selection = try #require(sessionBlockSelection(blockUpdate.selection))
        #expect(selection.blockIDs == [a, b])
        #expect(selection.anchor == a)
        #expect(selection.focus == b)
    }

    @Test("Cmd-A는 부분 블록 선택과 inactive에서 전체 visible block 선택으로 전환한다")
    func selectsAllVisibleBlocksFromBlockSelectionAndInactive() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([Block(id: a), Block(id: b)]),
            selection: .blocks(BlockSelection(blockIDs: [a]))
        )

        // When
        let allFromBlock = try #require(session.handleInput(.command(.selectAll)))
        _ = session.handleInput(.command(.escape))
        let allFromInactive = try #require(session.handleInput(.command(.selectAll)))

        // Then
        #expect(sessionBlockSelection(allFromBlock.selection)?.blockIDs == [a, b])
        #expect(sessionBlockSelection(allFromInactive.selection)?.blockIDs == [a, b])
    }

    @Test("Cmd-A는 빈 텍스트 블록도 텍스트 선택 상태를 거친 뒤 블록 선택으로 확장한다")
    func handlesSelectAllEdgeCases() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let emptySession = EditorSession(document: .singleParagraph("", id: a))
        let allBlocksSession = EditorSession(
            document: makeFlatDocument([Block(id: a), Block(id: b)]),
            selection: .blocks(BlockSelection(blockIDs: [a, b]))
        )

        // When
        let emptyTextUpdate = try #require(emptySession.handleInput(.command(.selectAll)))
        let emptyBlockUpdate = try #require(emptySession.handleInput(.command(.selectAll)))
        let allBlocksUpdate = allBlocksSession.handleInput(.command(.selectAll))

        // Then
        #expect(
            emptyTextUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: a, offset: 0),
                        focus: TextPosition(blockID: a, offset: 0)
                    )
                )
        )
        #expect(emptyBlockUpdate.selection == .blocks(BlockSelection(blockIDs: [a])))
        #expect(allBlocksUpdate == nil)
        let snapshot = allBlocksSession.render(in: EditorViewport(width: 240, scrollY: 0, height: 400))
        #expect(snapshot.selection == .blocks(BlockSelection(blockIDs: [a, b])))
    }

    @Test("다중 블록 텍스트의 Cmd-A는 걸친 블록 전체 텍스트를 먼저 선택한 뒤 전체 블록으로 확장한다")
    func escalatesCrossBlockTextSelectionInTwoStages() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "AAA")),
                Block(id: b, content: BlockContent(text: "BBB")),
                Block(id: c, content: BlockContent(text: "CCC")),
            ]),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: b, offset: 2),
                    focus: TextPosition(blockID: c, offset: 1)
                )
            )
        )

        // When
        let textUpdate = try #require(session.handleInput(.command(.selectAll)))
        let blockUpdate = try #require(session.handleInput(.command(.selectAll)))

        // Then
        #expect(
            textUpdate.selection == .text(
                TextSelection(
                    anchor: TextPosition(blockID: b, offset: 0),
                    focus: TextPosition(blockID: c, offset: 3)
                )
            )
        )
        #expect(sessionBlockSelection(blockUpdate.selection)?.blockIDs == [a, b, c])
    }
}
