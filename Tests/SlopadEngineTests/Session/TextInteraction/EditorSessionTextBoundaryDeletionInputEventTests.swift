import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 텍스트 경계 삭제 입력 이벤트")
struct EditorSessionTextBoundaryDeletionInputEventTests {
    @Test("Command-Delete 입력은 caret 이전 현재 블록 텍스트를 삭제한다")
    func deletesToTextStartInTextEditing() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("alpha beta", id: blockID),
            selection: .caret(blockID: blockID, offset: 6)
        )

        // When
        let update = try #require(session.handleInput(.command(.deleteToTextStart)))

        // Then
        #expect(session.document.block(blockID)?.content.text == "beta")
        #expect(update.selection == .caret(blockID: blockID, offset: 0))
        #expect(update.history.canUndo)
    }

    @Test("Option-Delete 입력은 공백 기준 이전 단어 경계부터 caret까지 삭제한다")
    func deletesToPreviousSpaceDelimitedWordBoundary() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("alpha beta gamma", id: blockID),
            selection: .caret(blockID: blockID, offset: 16)
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let update = try #require(
            session.handleInput(.command(.deleteWordBackward(viewport: viewport)))
        )

        // Then
        #expect(session.document.block(blockID)?.content.text == "alpha beta ")
        #expect(update.selection == .caret(blockID: blockID, offset: 11))
        #expect(update.history.canUndo)
    }

    @Test("modifier delete 입력은 텍스트 선택 범위를 먼저 삭제한다")
    func modifierDeleteRemovesSelectedTextFirst() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("alpha beta", id: blockID),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 2),
                    focus: TextPosition(blockID: blockID, offset: 7)
                )
            )
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let update = try #require(
            session.handleInput(.command(.deleteWordBackward(viewport: viewport)))
        )

        // Then
        #expect(session.document.block(blockID)?.content.text == "aleta")
        #expect(update.selection == .caret(blockID: blockID, offset: 2))
        #expect(update.history.canUndo)
    }

    @Test("Option-Delete는 backend가 계산한 단어 삭제 범위를 엔진 command로 적용한다")
    func wordDeletionUsesBackendRange() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.deletionRangeResolver = { _ in TextRange(2, 4) }
        let session = EditorSession(
            document: .singleParagraph("你好世界", id: blockID),
            selection: .caret(blockID: blockID, offset: 4),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let update = try #require(
            session.handleInput(.command(.deleteWordBackward(viewport: viewport)))
        )

        // Then
        let request = try #require(layouter.deletionRangeRequests.last)
        #expect(request.direction == .backward)
        #expect(request.destination == .word)
        #expect(request.selection.rangeInSingleBlock == .point(4))
        #expect(request.measureRequest.text == "你好世界")
        #expect(session.document.block(blockID)?.content.text == "你好")
        #expect(update.selection == .caret(blockID: blockID, offset: 2))
        #expect(update.history.canUndo)
    }

    @Test("backend가 텍스트 범위 밖 단어 삭제 범위를 반환하면 문서를 변경하지 않는다")
    func rejectsInvalidBackendDeletionRange() {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.deletionRangeResolver = { _ in TextRange(2, 5) }
        let session = EditorSession(
            document: .singleParagraph("你好世界", id: blockID),
            selection: .caret(blockID: blockID, offset: 4),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let update = session.handleInput(
            .command(.deleteWordBackward(viewport: viewport))
        )

        // Then
        #expect(update == nil)
        #expect(session.document.block(blockID)?.content.text == "你好世界")
    }

    @Test("backend가 음수 또는 역전된 단어 삭제 범위를 반환하면 문서를 변경하지 않는다")
    func rejectsMalformedBackendDeletionRanges() {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        var backendRange = TextRange(0, 2)
        backendRange.lowerBound = -1
        layouter.deletionRangeResolver = { _ in backendRange }
        let session = EditorSession(
            document: .singleParagraph("abcd", id: blockID),
            selection: .caret(blockID: blockID, offset: 4),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let negativeRangeUpdate = session.handleInput(
            .command(.deleteWordBackward(viewport: viewport))
        )
        backendRange = TextRange(0, 2)
        backendRange.lowerBound = 3
        let reversedRangeUpdate = session.handleInput(
            .command(.deleteWordBackward(viewport: viewport))
        )

        // Then
        #expect(negativeRangeUpdate == nil)
        #expect(reversedRangeUpdate == nil)
        #expect(session.document.block(blockID)?.content.text == "abcd")
    }

    @Test("접힌 backward 단어 삭제 범위가 focus에서 끝나지 않으면 문서를 변경하지 않는다")
    func rejectsBackwardDeletionRangeDetachedFromFocus() {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.deletionRangeResolver = { _ in TextRange(1, 3) }
        let session = EditorSession(
            document: .singleParagraph("abcd", id: blockID),
            selection: .caret(blockID: blockID, offset: 4),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let update = session.handleInput(
            .command(.deleteWordBackward(viewport: viewport))
        )

        // Then
        #expect(update == nil)
        #expect(session.document.block(blockID)?.content.text == "abcd")
    }

    @Test("펼쳐진 선택의 단어 삭제 범위가 선택과 다르면 문서를 변경하지 않는다")
    func rejectsDeletionRangeDifferentFromSelection() {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.deletionRangeResolver = { _ in TextRange(0, 2) }
        let session = EditorSession(
            document: .singleParagraph("abcd", id: blockID),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 1),
                    focus: TextPosition(blockID: blockID, offset: 3)
                )
            ),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let update = session.handleInput(
            .command(.deleteWordBackward(viewport: viewport))
        )

        // Then
        #expect(update == nil)
        #expect(session.document.block(blockID)?.content.text == "abcd")
    }

    @Test("접힌 forward 단어 삭제 범위는 focus에서 시작해야 유효하다")
    func validatesForwardDeletionRangeFromFocus() {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("abcd", id: blockID))
        let position = TextPosition(blockID: blockID, offset: 2)
        let selection = TextSelection(anchor: position, focus: position)
        let request = BlockMeasureRequest(
            blockID: blockID,
            text: "abcd",
            kind: .paragraph,
            availableWidth: 320,
            depth: 0
        )

        // When
        let attachedRangeIsValid = session.isValidTextDeletionRange(
            TextRange(2, 4),
            for: selection,
            direction: .forward,
            destination: .word,
            in: request
        )
        let detachedRangeIsValid = session.isValidTextDeletionRange(
            TextRange(1, 3),
            for: selection,
            direction: .forward,
            destination: .word,
            in: request
        )

        // Then
        #expect(attachedRangeIsValid)
        #expect(!detachedRangeIsValid)
    }

    @Test("조합 중 단어 삭제는 marked text를 먼저 commit한 canonical 요청에 적용한다")
    func wordDeletionCommitsCompositionBeforeApplyingRange() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.deletionRangeResolver = { request in
            request.measureRequest.text == "a한국어d" ? TextRange(1, 4) : nil
        }
        let session = EditorSession(
            document: .singleParagraph("abcd", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)
        _ = session.handleInput(
            .beginComposition(
                blockID: blockID,
                replacementRange: TextRange(1, 3),
                text: "한국어"
            )
        )

        // When
        let update = try #require(
            session.handleInput(.command(.deleteWordBackward(viewport: viewport)))
        )

        // Then
        #expect(layouter.deletionRangeRequests.last?.measureRequest.text == "a한국어d")
        #expect(session.composition == nil)
        #expect(session.document.block(blockID)?.content.text == "ad")
        #expect(update.selection == .caret(blockID: blockID, offset: 1))

        let undoUpdate = try #require(session.handleInput(.command(.undo)))
        #expect(session.document.block(blockID)?.content.text == "abcd")
        #expect(undoUpdate.selection == .caret(blockID: blockID, offset: 1))

        let redoUpdate = try #require(session.handleInput(.command(.redo)))
        #expect(session.document.block(blockID)?.content.text == "ad")
        #expect(redoUpdate.selection == .caret(blockID: blockID, offset: 1))
    }
}
