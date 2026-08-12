import SlopadCoreModel
import Testing

@testable import SlopadEditorEngine

@Suite("에디터 세션 텍스트 포인터 drag 입력 이벤트")
struct EditorSessionTextPointerDragInputEventTests {
    @Test("본문 drag 포인터 이벤트는 같은 블록 안에서 텍스트 선택 범위로 해석된다")
    func handlesPointerTextSelectionDragEvent() throws {
        // Given
        let blockID: BlockID = "a"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [blockID: BlockMeasurement(height: 10)]
        layouter.textPositionResolver = { blockID, point in
            TextPosition(blockID: blockID, offset: point.x < 40 ? 1 : 4)
        }
        let session = EditorSession(
            document: .singleParagraph("Body", id: blockID),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let beginUpdate = try #require(
            session.handleInput(
                .pointer(
                    .beginTextSelection(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    )
                )
            )
        )
        let dragUpdate = try #require(
            session.handleInput(
                .pointer(
                    .updateTextSelection(
                        documentPoint: EditorPoint(x: 80, y: 5),
                        viewport: viewport
                    )
                )
            )
        )
        _ = try #require(session.handleInput(.pointer(.endTextSelection)))

        // Then
        #expect(beginUpdate.selection == .caret(blockID: blockID, offset: 1))
        #expect(
            dragUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 1),
                        focus: TextPosition(blockID: blockID, offset: 4)
                    )
                )
        )
        #expect(session.activeTextRange() == TextRange(1, 4))
        #expect(layouter.textPositionRequests.map(\.blockID) == [blockID, blockID])
        #expect(
            layouter.textPositionRequests.map(\.point)
                == [EditorPoint(x: 20, y: 5), EditorPoint(x: 80, y: 5)]
        )
        #expect(session.textSelectionDragAnchor == nil)
    }

    @Test("본문 text drag가 다른 블록으로 넘어가면 그 블록의 정확한 글자까지 선택한다")
    func extendsTextDragIntoFocusedBlock() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 10),
            c: BlockMeasurement(height: 10),
        ]
        layouter.textPositionResolver = { blockID, _ in
            TextPosition(blockID: blockID, offset: blockID == a ? 1 : 1)
        }
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "abcdef")),
                Block(id: b, content: BlockContent(text: "B")),
                Block(id: c, content: BlockContent(text: "C")),
            ]),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
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
        let boundaryUpdate = try #require(
            session.handleInput(
                .pointer(
                    .updateTextSelection(
                        documentPoint: EditorPoint(x: 20, y: 25),
                        viewport: viewport
                    )
                )
            )
        )
        let blockDragUpdate = session.handleInput(
            .pointer(
                .extendBlockSelection(
                    documentPoint: EditorPoint(x: 20, y: 25),
                    region: .gutter,
                    viewport: viewport
                )
            )
        )

        // Then
        #expect(
            boundaryUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: a, offset: 1),
                        focus: TextPosition(blockID: c, offset: 1)
                    )
                )
        )
        #expect(session.activeTextPosition()?.blockID == c)
        #expect(session.activeTextRange() == TextRange(0, 1))
        #expect(blockDragUpdate == nil)
        #expect(session.textSelectionDragAnchor == TextPosition(blockID: a, offset: 1))
        #expect(layouter.textPositionRequests.map(\.blockID) == [a, c])
    }

    @Test("본문에서 시작한 drag는 구조 영역으로 이동해도 text mode를 유지한다")
    func keepsTextModeAfterMovingIntoStructuralArea() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 10),
            c: BlockMeasurement(height: 10),
        ]
        layouter.textPositionResolver = { blockID, _ in
            TextPosition(blockID: blockID, offset: 1)
        }
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "B")),
                Block(id: c, content: BlockContent(text: "C")),
            ]),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        _ = try #require(
            session.handleInput(
                .pointer(
                    .beginTextSelection(
                        documentPoint: EditorPoint(x: 20, y: 15),
                        viewport: viewport
                    )
                )
            )
        )
        let dragUpdate = try #require(
            session.handleInput(
                .pointer(
                    .updateTextSelection(
                        documentPoint: EditorPoint(x: 20, y: 0),
                        viewport: viewport
                    )
                )
            )
        )
        let continuedUpdate = session.handleInput(
            .pointer(
                .extendBlockSelection(
                    documentPoint: EditorPoint(x: 0, y: 25),
                    region: .gutter,
                    viewport: viewport
                )
            )
        )

        // Then
        #expect(
            dragUpdate.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: b, offset: 1),
                        focus: TextPosition(blockID: a, offset: 1)
                    )
                )
        )
        #expect(continuedUpdate == nil)
        #expect(session.activeTextPosition()?.blockID == a)
        #expect(session.textSelectionDragAnchor == TextPosition(blockID: b, offset: 1))
        #expect(session.blockSelectionDragAnchor == nil)
    }

    @Test("빈 블록에서 위로 drag하면 빈 블록을 anchor로 쓰지 않고 직전 내용 끝에서 선택한다")
    func emptyBlockUpwardDragAnchorsAtPreviousNonemptyTextEdge() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let empty: BlockID = "empty"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 10),
            empty: BlockMeasurement(height: 10),
        ]
        layouter.textPositionResolver = { blockID, _ in
            TextPosition(blockID: blockID, offset: blockID == empty ? 0 : 1)
        }
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "Alpha")),
                Block(id: b, content: BlockContent(text: "Bravo")),
                Block(id: empty, content: BlockContent(text: "")),
            ]),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let begin = try #require(
            session.handleInput(
                .pointer(
                    .beginTextSelection(
                        documentPoint: EditorPoint(x: 20, y: 25),
                        viewport: viewport
                    ))))
        let drag = try #require(
            session.handleInput(
                .pointer(
                    .updateTextSelection(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    ))))

        // Then
        #expect(begin.selection == .caret(blockID: empty, offset: 0))
        #expect(
            drag.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: b, offset: 5),
                        focus: TextPosition(blockID: a, offset: 1)
                    )
                )
        )
    }

    @Test("빈 블록 click은 drag 방향이 생기지 않으면 그 블록 caret을 유지한다")
    func emptyBlockClickKeepsEditableCaret() throws {
        // Given
        let empty: BlockID = "empty"
        let layouter = SpyBlockTextLayouter()
        layouter.measurementsByBlockID = [empty: BlockMeasurement(height: 10)]
        layouter.textPositionResolver = { blockID, _ in
            TextPosition(blockID: blockID, offset: 0)
        }
        let session = EditorSession(
            document: .singleParagraph("", id: empty),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        _ = try #require(
            session.handleInput(
                .pointer(
                    .beginTextSelection(
                        documentPoint: EditorPoint(x: 20, y: 5),
                        viewport: viewport
                    ))))
        _ = try #require(session.handleInput(.pointer(.endTextSelection)))

        // Then
        #expect(session.editorModel.selection == .caret(blockID: empty, offset: 0))
        #expect(session.textSelectionDragAnchor == nil)
        #expect(session.textSelectionPendingOrigin == nil)
    }
}
