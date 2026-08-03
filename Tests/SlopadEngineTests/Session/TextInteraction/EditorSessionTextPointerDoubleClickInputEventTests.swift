import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 텍스트 포인터 double-click 입력 이벤트")
struct EditorSessionTextPointerDoubleClickInputEventTests {
    @Test("본문 double-click은 caret에서 단어를 선택하고 선택 range 첫 클릭이 caret을 놓아도 전체 블록 텍스트로 확장한다")
    func selectsWordThenAllTextFromPointerDoubleClick() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [blockID: BlockMeasurement(height: 10)]
        layouter.textPositionsByBlockID[blockID] = TextPosition(blockID: blockID, offset: 8)
        let session = EditorSession(
            document: .singleParagraph("alpha beta gamma", id: blockID),
            selection: .caret(blockID: blockID, offset: 8),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let wordUpdate = try #require(
            session.handleInput(
                .pointer(
                    .selectWordOrAllText(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    )
                )
            )
        )
        _ = try #require(
            session.handleInput(
                .pointer(
                    .beginTextSelection(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    )
                )
            )
        )
        let allTextUpdate = try #require(
            session.handleInput(
                .pointer(
                    .selectWordOrAllText(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    )
                )
            )
        )
        let repeatedUpdate = try #require(
            session.handleInput(
                .pointer(
                    .selectWordOrAllText(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    )
                )
            )
        )

        // Then
        #expect(
            wordUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 6),
                        focus: TextPosition(blockID: blockID, offset: 10)
                    )
                )
        )
        #expect(
            allTextUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 0),
                        focus: TextPosition(blockID: blockID, offset: 16)
                    )
                )
        )
        #expect(repeatedUpdate.selection == allTextUpdate.selection)
    }

    @Test("단어 안 caret 상태에서 double-click하면 이전 double-click 후보가 남아 있어도 단어 선택으로 돌아간다")
    func selectsWordFromCaretInsidePreviousWord() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [blockID: BlockMeasurement(height: 10)]
        layouter.textPositionsByBlockID[blockID] = TextPosition(blockID: blockID, offset: 8)
        let session = EditorSession(
            document: .singleParagraph("alpha beta gamma", id: blockID),
            selection: .caret(blockID: blockID, offset: 8),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        _ = try #require(
            session.handleInput(
                .pointer(
                    .selectWordOrAllText(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    )
                )
            )
        )
        _ = try #require(
            session.handleInput(
                .pointer(
                    .beginTextSelection(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    )
                )
            )
        )
        _ = try #require(
            session.handleInput(
                .pointer(
                    .beginTextSelection(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    )
                )
            )
        )
        let wordUpdate = try #require(
            session.handleInput(
                .pointer(
                    .selectWordOrAllText(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    )
                )
            )
        )

        // Then
        #expect(
            wordUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 6),
                        focus: TextPosition(blockID: blockID, offset: 10)
                    )
                )
        )
    }

    @Test("본문 double-click은 backend가 계산한 단어 범위를 선택한다")
    func selectsBackendWordRange() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [blockID: BlockMeasurement(height: 10)]
        layouter.textPositionsByBlockID[blockID] = TextPosition(blockID: blockID, offset: 2)
        layouter.wordRangeResolver = { _ in TextRange(1, 3) }
        let session = EditorSession(
            document: .singleParagraph("你好世界", id: blockID),
            selection: .caret(blockID: blockID, offset: 2),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let update = try #require(
            session.handleInput(
                .pointer(
                    .selectWordOrAllText(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    )
                )
            )
        )

        // Then
        let request = try #require(layouter.wordRangeRequests.last)
        #expect(request.position == TextPosition(blockID: blockID, offset: 2))
        #expect(request.measureRequest.text == "你好世界")
        #expect(request.measureRequest.availableWidth == viewport.width)
        #expect(
            update.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 1),
                        focus: TextPosition(blockID: blockID, offset: 3)
                    )
                )
        )
    }

    @Test("backend가 텍스트 범위 밖 단어 범위를 반환하면 선택을 변경하지 않는다")
    func rejectsInvalidBackendWordRange() {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [blockID: BlockMeasurement(height: 10)]
        layouter.textPositionsByBlockID[blockID] = TextPosition(blockID: blockID, offset: 2)
        layouter.wordRangeResolver = { _ in TextRange(0, 5) }
        let session = EditorSession(
            document: .singleParagraph("你好世界", id: blockID),
            selection: .caret(blockID: blockID, offset: 2),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let update = session.handleInput(
            .pointer(
                .selectWordOrAllText(
                    documentPoint: EditorPoint(x: 20, y: 5),
                    viewport: viewport
                )
            )
        )

        // Then
        #expect(update == nil)
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 2))
    }

    @Test("backend가 음수 또는 역전된 단어 범위를 반환하면 선택을 변경하지 않는다")
    func rejectsMalformedBackendWordRanges() {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [blockID: BlockMeasurement(height: 10)]
        layouter.textPositionsByBlockID[blockID] = TextPosition(blockID: blockID, offset: 2)
        var backendRange = TextRange(0, 2)
        backendRange.lowerBound = -1
        layouter.wordRangeResolver = { _ in backendRange }
        let session = EditorSession(
            document: .singleParagraph("abcd", id: blockID),
            selection: .caret(blockID: blockID, offset: 2),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let negativeRangeUpdate = session.handleInput(
            .pointer(
                .selectWordOrAllText(
                    documentPoint: EditorPoint(x: 20, y: 5),
                    viewport: viewport
                )
            )
        )
        backendRange = TextRange(0, 2)
        backendRange.lowerBound = 3
        let reversedRangeUpdate = session.handleInput(
            .pointer(
                .selectWordOrAllText(
                    documentPoint: EditorPoint(x: 20, y: 5),
                    viewport: viewport
                )
            )
        )

        // Then
        #expect(negativeRangeUpdate == nil)
        #expect(reversedRangeUpdate == nil)
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 2))
    }
}
