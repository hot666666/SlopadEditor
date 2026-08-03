@testable import SlopadEngine
import SlopadCoreModel
import Testing

@Suite("런타임 렌더 damage")
struct EditorSessionRenderDamageTests {
    @Test("높이가 유지되는 텍스트 편집은 변경 block frame만 다시 그린다")
    func textEditWithUnchangedHeightDamagesOnlyChangedBlock() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "a")),
            Block(id: b, content: BlockContent(text: "b")),
            Block(id: c, content: BlockContent(text: "c")),
        ])
        let layouter = RecordingBlockTextLayouter(
            measurementsByBlockID: [
                a: BlockMeasurement(height: 20),
                b: BlockMeasurement(height: 20),
                c: BlockMeasurement(height: 20),
            ]
        )
        let session = EditorSession(
            document: document,
            selection: .caret(blockID: b, offset: 1),
            textLayouter: layouter
        )
        let viewport = EditorViewport(width: 200, scrollY: 0, height: 100)
        _ = session.render(in: viewport)
        let expectedRects = [EditorRect(x: 0, y: 20, width: 200, height: 20)]

        // When
        let update = try #require(session.handleInput(.command(.insertText("!"))))
        let rects = session.redrawRects(for: update, in: viewport)

        // Then
        #expect(rects == expectedRects)
    }

    @Test("높이가 바뀌는 텍스트 편집은 변경 block부터 viewport 끝까지 다시 그린다")
    func textEditWithHeightChangeDamagesTailFromChangedBlock() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "a")),
            Block(id: b, content: BlockContent(text: "b")),
            Block(id: c, content: BlockContent(text: "c")),
        ])
        let session = EditorSession(
            document: document,
            selection: .caret(blockID: b, offset: 1),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 0)
        )
        let viewport = EditorViewport(width: 200, scrollY: 0, height: 100)
        _ = session.render(in: viewport)
        let expectedRects = [EditorRect(x: 0, y: 10, width: 200, height: 90)]

        // When
        let update = try #require(session.handleInput(.command(.insertText("\n"))))
        let rects = session.redrawRects(for: update, in: viewport)

        // Then
        #expect(rects == expectedRects)
    }

    @Test("구조 편집은 영향 시작 block부터 viewport 끝까지 다시 그린다")
    func structuralEditDamagesTailFromAffectedBlock() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "a")),
            Block(id: b, content: BlockContent(text: "bc")),
            Block(id: c, content: BlockContent(text: "c")),
        ])
        let session = EditorSession(
            document: document,
            selection: .caret(blockID: b, offset: 1),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 0)
        )
        let viewport = EditorViewport(width: 200, scrollY: 0, height: 100)
        _ = session.render(in: viewport)
        let expectedRects = [EditorRect(x: 0, y: 10, width: 200, height: 90)]

        // When
        let update = try #require(session.handleInput(.command(.enter)))
        let rects = session.redrawRects(for: update, in: viewport)

        // Then
        #expect(rects == expectedRects)
    }

    @Test("전체 block 삭제 후 빈 문단 reset은 viewport 전체를 다시 그린다")
    func deletingAllBlocksDamagesFullViewport() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "a")),
            Block(id: b, content: BlockContent(text: "b")),
            Block(id: c, content: BlockContent(text: "c")),
        ])
        let session = EditorSession(
            document: document,
            selection: .blocks(BlockSelection(blockIDs: [a, b, c])),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 0)
        )
        let viewport = EditorViewport(width: 200, scrollY: 0, height: 100)
        _ = session.render(in: viewport)
        let expectedRects = [EditorRect(x: 0, y: 0, width: 200, height: 100)]

        // When
        let update = try #require(session.handleInput(.command(.deleteBackward)))
        let rects = session.redrawRects(for: update, in: viewport)

        // Then
        #expect(rects == expectedRects)
    }

    @Test("text layout backend 교체는 affected block anchor 없이 viewport 전체를 다시 그린다")
    func textLayoutBackendReplacementDamagesFullViewport() {
        // Given
        let document = makeFlatDocument([
            Block(id: "a", content: BlockContent(text: "a")),
            Block(id: "b", content: BlockContent(text: "b")),
        ])
        let session = EditorSession(
            document: document,
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 0)
        )
        let viewport = EditorViewport(width: 200, scrollY: 0, height: 100)
        _ = session.render(in: viewport)
        let expectedRects = [EditorRect(x: 0, y: 0, width: 200, height: 100)]

        // When
        let update = session.replaceTextLayoutBackend(
            with: DeterministicBlockTextLayouter(lineHeight: 20, verticalPadding: 0)
        )
        let rects = session.redrawRects(for: update, in: viewport)

        // Then
        #expect(update.invalidation.blockIDs.isEmpty)
        #expect(rects == expectedRects)
    }

    @Test("전체 measurement 무효화는 affected block anchor 없이 viewport 전체를 다시 그린다")
    func invalidatingAllMeasurementsDamagesFullViewport() {
        // Given
        let document = makeFlatDocument([
            Block(id: "a", content: BlockContent(text: "a")),
            Block(id: "b", content: BlockContent(text: "b")),
        ])
        let session = EditorSession(
            document: document,
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 0)
        )
        let viewport = EditorViewport(width: 200, scrollY: 0, height: 100)
        _ = session.render(in: viewport)
        let expectedRects = [EditorRect(x: 0, y: 0, width: 200, height: 100)]

        // When
        let update = session.invalidateAllLayoutMeasurements()
        let rects = session.redrawRects(for: update, in: viewport)

        // Then
        #expect(update.invalidation.blockIDs.isEmpty)
        #expect(rects == expectedRects)
    }

    @Test("선택만 바뀌면 이전 선택 block과 새 선택 block만 다시 그린다")
    func selectionChangeDamagesPreviousAndCurrentSelectionBlocks() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "a")),
            Block(id: b, content: BlockContent(text: "b")),
            Block(id: c, content: BlockContent(text: "c")),
        ])
        let session = EditorSession(
            document: document,
            selection: .caret(blockID: a, offset: 0),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 0)
        )
        let viewport = EditorViewport(width: 200, scrollY: 0, height: 100)
        _ = session.render(in: viewport)
        let expectedRects = [
            EditorRect(x: 0, y: 0, width: 200, height: 10),
            EditorRect(x: 0, y: 20, width: 200, height: 10),
        ]

        // When
        let update = try #require(
            session.handleInput(
                .pointer(
                    .selectBlockRange(
                        anchor: BlockHitTestResult(blockID: c, region: .gutter),
                        focus: BlockHitTestResult(blockID: c, region: .gutter)
                    )
                )
            )
        )
        let rects = session.redrawRects(for: update, in: viewport)

        // Then
        #expect(update.previousSelection == .caret(blockID: a, offset: 0))
        #expect(rects == expectedRects)
    }
}
