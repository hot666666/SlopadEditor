import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 레이아웃 무효화")
struct EditorSessionLayoutInvalidationTests {
    @Test("캐시된 레이아웃 이후 명령이 문서를 바꾸면 다음 렌더링에서 다시 배치한다")
    func relayoutsAfterDocumentCommand() {
        // Given
        let blockID: BlockID = "a"
        let textLayouter = RecordingBlockTextLayouter()
        let session = EditorSession(
            document: .singleParagraph("", id: blockID),
            textLayouter: textLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()

        // When
        _ = session.handleCommand(.insertText("X"))
        _ = session.render(in: viewport)

        // Then
        #expect(textLayouter.measuredBlockIDs == [blockID])
    }

    @Test("text layout backend 교체는 새 backend로 전체 geometry를 다시 측정한다")
    func replacesTextLayoutBackend() {
        // Given
        let blockID: BlockID = "a"
        let originalLayouter = RecordingBlockTextLayouter(
            measurementsByBlockID: [blockID: BlockMeasurement(height: 12)]
        )
        let replacementLayouter = RecordingBlockTextLayouter(
            measurementsByBlockID: [blockID: BlockMeasurement(height: 48)]
        )
        let session = EditorSession(
            document: .singleParagraph("Hi", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: originalLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.handleInput(
            .beginComposition(
                blockID: blockID,
                replacementRange: TextRange(1, 1),
                text: "marked"
            )
        )
        let originalSnapshot = session.render(in: viewport)
        originalLayouter.measuredBlockIDs.removeAll()

        // When
        let update = session.replaceTextLayoutBackend(with: replacementLayouter)
        let replacementSnapshot = session.render(in: viewport)

        // Then
        #expect(update.invalidation.blockIDs.isEmpty)
        #expect(update.invalidation.layoutGeometryChanged)
        #expect(originalLayouter.measuredBlockIDs.isEmpty)
        #expect(replacementLayouter.measuredBlockIDs == [blockID])
        #expect(originalSnapshot.totalHeight == 12)
        #expect(replacementSnapshot.totalHeight == 48)
        #expect(update.selection == originalSnapshot.selection)
        #expect(update.composition == originalSnapshot.composition)
        #expect(update.history.canUndo == originalSnapshot.history.canUndo)
        #expect(update.history.canRedo == originalSnapshot.history.canRedo)
        #expect(
            replacementSnapshot.revision.textLayoutRevision
                == originalSnapshot.revision.textLayoutRevision + 1
        )
    }

    @Test("text layout backend 교체는 진행 중인 block drag의 이전 layout drop geometry를 제거한다")
    func clearsStaleBlockDragGeometry() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "B")),
            ]),
            selection: .blocks(BlockSelection(blockIDs: [a])),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 20, verticalPadding: 0)
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 200)
        _ = session.render(in: viewport)
        _ = try #require(
            session.handleInput(
                .pointer(
                    .beginBlockDrag(
                        documentPoint: EditorPoint(x: 4, y: 10),
                        viewport: viewport
                    )
                )
            )
        )
        _ = try #require(
            session.handleInput(
                .pointer(
                    .updateBlockDrag(
                        documentPoint: EditorPoint(x: 4, y: 35),
                        viewport: viewport
                    )
                )
            )
        )
        #expect(session.blockDrag?.dropTarget != nil)
        #expect(session.blockDrag?.dropIndicator != nil)

        // When
        _ = session.replaceTextLayoutBackend(
            with: DeterministicBlockTextLayouter(lineHeight: 40, verticalPadding: 0)
        )

        // Then
        #expect(session.blockDrag?.blockIDs == [a])
        #expect(session.blockDrag?.dropTarget == nil)
        #expect(session.blockDrag?.dropIndicator == nil)
    }

    @Test("특정 블록 측정 무효화는 세션을 통해 해당 블록만 다시 측정한다")
    func invalidatesSpecificMeasurements() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let textLayouter = RecordingBlockTextLayouter(
            measurementsByBlockID: [
                a: BlockMeasurement(height: 10),
                b: BlockMeasurement(height: 12),
            ]
        )
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "B")),
            ]),
            textLayouter: textLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()  // spy only

        // When
        let update = session.invalidateLayoutMeasurements(blockIDs: [b])
        _ = session.render(in: viewport)

        // Then
        #expect(update.invalidation.blockIDs == Set([b]))
        #expect(update.invalidation.layoutGeometryChanged)
        #expect(textLayouter.measuredBlockIDs == [b])
    }

    @Test("전체 블록 측정 무효화는 세션을 통해 모든 블록을 다시 측정한다")
    func invalidatesAllMeasurements() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let textLayouter = RecordingBlockTextLayouter(
            measurementsByBlockID: [
                a: BlockMeasurement(height: 10),
                b: BlockMeasurement(height: 12),
            ]
        )
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "B")),
            ]),
            textLayouter: textLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()  // spy only

        // When
        let update = session.invalidateAllLayoutMeasurements()
        _ = session.render(in: viewport)

        // Then
        #expect(update.invalidation.blockIDs.isEmpty)
        #expect(update.invalidation.layoutGeometryChanged)
        #expect(textLayouter.measuredBlockIDs == [a, b])
    }
}
