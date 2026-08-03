import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 backend 텍스트 네비게이션")
struct EditorSessionTextBackendNavigationTests {
    @Test("단어 이동은 composition이 반영된 유효 텍스트 요청과 backend 결과를 사용한다")
    func wordMovementUsesEffectiveCompositionRequest() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.navigationResolver = { request in
            let position = TextPosition(
                blockID: request.measureRequest.blockID,
                offset: 3,
                affinity: .downstream
            )
            return .selection(
                TextSelection(anchor: position, focus: position),
                context: nil
            )
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
                text: "한글"
            )
        )
        _ = session.handleInput(
            .activeTextSelectionChanged(
                blockID: blockID,
                selectedRange: TextRange.point(2)
            )
        )

        // When
        let update = try #require(
            session.handleInput(.command(.moveWordRight(viewport: viewport)))
        )

        // Then
        let request = try #require(layouter.navigationRequests.last)
        #expect(request.direction == .right)
        #expect(request.destination == .word)
        #expect(!request.extending)
        #expect(request.selection.rangeInSingleBlock == TextRange.point(2))
        #expect(request.measureRequest.text == "a한글d")
        #expect(request.measureRequest.availableWidth == viewport.width)
        #expect(
            update.selection
                == .caret(
                    TextPosition(blockID: blockID, offset: 3, affinity: .downstream)
                )
        )
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 1))
        #expect(session.composition != nil)
    }

    @Test("backend의 logical start 경계는 물리 키 방향과 무관하게 이전 블록 끝으로 이동한다")
    func logicalStartBoundaryMovesToPreviousBlockEnd() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let layouter = SpyBlockTextLayouter()
        layouter.navigationResolver = { _ in .boundary(.start) }
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "AB")),
                Block(id: b, content: BlockContent(text: "CD")),
            ]),
            selection: .caret(blockID: b, offset: 0),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let update = try #require(
            session.handleInput(.command(.moveRight(viewport: viewport)))
        )

        // Then
        #expect(update.selection == .caret(blockID: a, offset: 2))
    }

    @Test("backend의 logical end 경계는 물리 키 방향과 무관하게 다음 블록 시작으로 이동한다")
    func logicalEndBoundaryMovesToNextBlockStart() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let layouter = SpyBlockTextLayouter()
        layouter.navigationResolver = { _ in .boundary(.end) }
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "AB")),
                Block(id: b, content: BlockContent(text: "CD")),
            ]),
            selection: .caret(blockID: a, offset: 2),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let update = try #require(
            session.handleInput(.command(.moveLeft(viewport: viewport)))
        )

        // Then
        #expect(update.selection == .caret(blockID: b, offset: 0))
    }

    @Test("backend가 현재 선택을 그대로 반환하면 update를 만들지 않는다")
    func unchangedBackendSelectionIsNoOp() {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.navigationResolver = { .selection($0.selection, context: $0.context) }
        let session = EditorSession(
            document: .singleParagraph("abc", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let update = session.handleInput(.command(.moveLeft(viewport: viewport)))

        // Then
        #expect(update == nil)
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 1))
    }

    @Test("논리 offset이 같아도 backend visual context가 바뀌면 surface update를 만든다")
    func visualContextOnlyMovementProducesUpdate() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.navigationResolver = {
            .selection(
                $0.selection,
                context: TextNavigationContext(preferredInlineOffset: 37)
            )
        }
        let session = EditorSession(
            document: .singleParagraph("abc", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let firstUpdate = try #require(
            session.handleInput(.command(.moveRight(viewport: viewport)))
        )
        let snapshot = session.render(in: viewport)
        let secondUpdate = session.handleInput(.command(.moveRight(viewport: viewport)))

        // Then
        #expect(firstUpdate.selection == .caret(blockID: blockID, offset: 1))
        #expect(snapshot.activeTextInput?.navigationContext?.preferredInlineOffset == 37)
        #expect(layouter.navigationRequests.last?.context?.preferredInlineOffset == 37)
        #expect(secondUpdate == nil)
    }

    @Test("일반 선택 변경은 backend visual context를 제거한다")
    func selectionChangeClearsVisualContext() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.navigationResolver = {
            .selection(
                $0.selection,
                context: TextNavigationContext(preferredInlineOffset: 37)
            )
        }
        let session = EditorSession(
            document: .singleParagraph("abc", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)
        _ = try #require(session.handleInput(.command(.moveRight(viewport: viewport))))
        #expect(session.textNavigationRuntimeContext != nil)

        // When
        _ = session.handleInput(
            .activeTextSelectionChanged(
                blockID: blockID,
                selectedRange: TextRange.point(2)
            )
        )

        // Then
        #expect(session.textNavigationRuntimeContext == nil)
    }

    @Test("선택 offset이 같아도 composition 요청이 바뀌면 visual context를 제거한다")
    func compositionRequestChangeClearsVisualContext() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.navigationResolver = {
            .selection(
                $0.selection,
                context: TextNavigationContext(preferredInlineOffset: 37)
            )
        }
        let session = EditorSession(
            document: .singleParagraph("abc", id: blockID),
            selection: .caret(blockID: blockID, offset: 2),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)
        _ = try #require(session.handleInput(.command(.moveRight(viewport: viewport))))
        #expect(session.textNavigationRuntimeContext != nil)

        // When
        _ = session.handleInput(
            .beginComposition(
                blockID: blockID,
                replacementRange: TextRange(1, 2),
                text: "z"
            )
        )

        // Then
        #expect(session.activeTextRange() == .point(2))
        #expect(session.textNavigationRuntimeContext == nil)
    }

    @Test("backend가 다른 블록이나 범위 밖 위치를 반환하면 선택을 변경하지 않는다")
    func rejectsInvalidBackendSelections() {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        let session = EditorSession(
            document: .singleParagraph("abc", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        layouter.navigationResolver = { _ in
            let position = TextPosition(blockID: "other", offset: 1)
            return .selection(
                TextSelection(anchor: position, focus: position),
                context: nil
            )
        }
        let wrongBlockUpdate = session.handleInput(.command(.moveLeft(viewport: viewport)))
        layouter.navigationResolver = { request in
            let position = TextPosition(
                blockID: request.measureRequest.blockID,
                offset: request.measureRequest.text.count + 1
            )
            return .selection(
                TextSelection(anchor: position, focus: position),
                context: nil
            )
        }
        let invalidOffsetUpdate = session.handleInput(.command(.moveLeft(viewport: viewport)))

        // Then
        #expect(wrongBlockUpdate == nil)
        #expect(invalidOffsetUpdate == nil)
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 1))
    }

    @Test("비확장 이동에서 backend가 펼쳐진 선택을 반환하면 선택과 visual context를 변경하지 않는다")
    func rejectsExpandedSelectionForNonExtendingMovement() {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.navigationResolver = { request in
            .selection(
                TextSelection(
                    anchor: TextPosition(blockID: request.measureRequest.blockID, offset: 0),
                    focus: TextPosition(blockID: request.measureRequest.blockID, offset: 2)
                ),
                context: TextNavigationContext(preferredInlineOffset: 24)
            )
        }
        let session = EditorSession(
            document: .singleParagraph("abc", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let update = session.handleInput(.command(.moveRight(viewport: viewport)))

        // Then
        #expect(update == nil)
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 1))
        #expect(session.textNavigationRuntimeContext == nil)
    }

    @Test("선택 확장은 backend focus를 적용하되 엔진 anchor를 유지한다")
    func extensionPreservesEngineAnchor() throws {
        // Given
        let blockID: BlockID = "a"
        let originalAnchor = TextPosition(blockID: blockID, offset: 3)
        let layouter = SpyBlockTextLayouter()
        layouter.navigationResolver = { request in
            .selection(
                TextSelection(
                    anchor: TextPosition(blockID: request.measureRequest.blockID, offset: 0),
                    focus: TextPosition(
                        blockID: request.measureRequest.blockID,
                        offset: 2,
                        affinity: .upstream
                    )
                ),
                context: TextNavigationContext(preferredInlineOffset: 42)
            )
        }
        let session = EditorSession(
            document: .singleParagraph("abcd", id: blockID),
            selection: .text(
                TextSelection(
                    anchor: originalAnchor,
                    focus: TextPosition(blockID: blockID, offset: 1)
                )
            ),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 320, scrollY: 0, height: 240)

        // When
        let update = try #require(
            session.handleInput(.command(.extendCharacterRight(viewport: viewport)))
        )

        // Then
        #expect(
            update.selection
                == .text(
                    TextSelection(
                        anchor: originalAnchor,
                        focus: TextPosition(
                            blockID: blockID,
                            offset: 2,
                            affinity: .upstream
                        )
                    )
                )
        )
        #expect(session.textNavigationRuntimeContext?.backendContext.preferredInlineOffset == 42)
    }
}
