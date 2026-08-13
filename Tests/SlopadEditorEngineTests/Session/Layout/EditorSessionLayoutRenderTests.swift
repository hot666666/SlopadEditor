import Testing

@testable import SlopadEditorEngine
import SlopadEditorCoreModel

@Suite("에디터 세션 레이아웃 렌더링")
struct EditorSessionLayoutRenderTests {
    @Test("스크롤된 뷰포트 렌더링은 재배치 없이 뷰포트 블록만 반환한다")
    func rendersScrolledViewportWithoutRelayout() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "B")),
            Block(id: c, content: BlockContent(text: "C")),
        ])
        let textLayouter = RecordingBlockTextLayouter(
            measurementsByBlockID: [
                a: BlockMeasurement(height: 10),
                b: BlockMeasurement(height: 10),
                c: BlockMeasurement(height: 10),
            ]
        )
        let session = EditorSession(
            document: document,
            textLayouter: textLayouter
        )
        let topViewport = EditorViewport(width: 240, scrollY: 0, height: 10)
        let scrolledViewport = EditorViewport(width: 240, scrollY: 10, height: 10)

        // When
        let topSnapshot = session.render(in: topViewport)
        textLayouter.measuredBlockIDs.removeAll()
        let scrolledSnapshot = session.render(in: scrolledViewport)

        // Then
        #expect(topSnapshot.visibleBlocks.map(\.id) == [a])
        #expect(scrolledSnapshot.visibleBlocks.map(\.id) == [b])
        #expect(textLayouter.measuredBlockIDs.isEmpty)
    }

    @Test("reveal frame 조회는 현재 렌더 범위 밖 블록도 layout snapshot에서 찾는다")
    func returnsRevealFrameOutsideCurrentRenderRange() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "B")),
            Block(id: c, content: BlockContent(text: "C")),
        ])
        let session = EditorSession(
            document: document,
            textLayouter: RecordingBlockTextLayouter(
                measurementsByBlockID: [
                    a: BlockMeasurement(height: 10),
                    b: BlockMeasurement(height: 12),
                    c: BlockMeasurement(height: 14),
                ]
            )
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 10)

        // When
        let snapshot = session.render(in: viewport)
        let frame = try #require(session.blockRevealFrame(for: c, viewport: viewport))

        // Then
        #expect(snapshot.visibleBlocks.map(\.id) == [a])
        #expect(frame == EditorRect(x: 0, y: 22, width: 240, height: 14))
    }

    @Test("큰 문서 reveal frame은 현재 viewport 밖 block을 demand measure해서 반환한다")
    func revealFrameDemandMeasuresOutsideLazyViewport() throws {
        // Given
        let target: BlockID = "block-400"
        let document = makeFlatDocument(
            (0..<600).map { index in
                Block(id: BlockID("block-\(index)"), content: BlockContent(text: "x"))
            }
        )
        let textLayouter = RecordingBlockTextLayouter(fallbackBaseHeight: 35)
        let session = EditorSession(
            document: document,
            textLayouter: textLayouter
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 120)
        _ = session.render(in: viewport)
        textLayouter.measuredBlockIDs.removeAll()

        // When
        let frame = try #require(session.blockRevealFrame(for: target, viewport: viewport))

        // Then
        #expect(textLayouter.measuredBlockIDs == [target])
        #expect(frame == EditorRect(x: 0, y: 400 * 36, width: 240, height: 36))
    }

    @Test("활성 텍스트 descriptor는 세션이 layout frame과 텍스트 geometry를 합성해 만든다")
    func rendersActiveTextInputDescriptor() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let geometry = SpyBlockTextLayouter()
        geometry.measurementsByBlockID = [
            a: BlockMeasurement(height: 10),
            b: BlockMeasurement(height: 14),
        ]
        geometry.textFramesByBlockID[b] = EditorRect(x: 12, y: 3, width: 120, height: 9)
        let session = EditorSession(
            document: makeFlatDocument([
                Block(id: a, content: BlockContent(text: "A")),
                Block(id: b, content: BlockContent(text: "Body")),
            ]),
            selection: .caret(blockID: b, offset: 2),
            textLayouter: geometry
        )
        let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

        // When
        let snapshot = session.render(in: viewport)
        let inputDescriptor = try #require(snapshot.activeTextInput)
        let request = inputDescriptor.renderDescriptor.measureRequest

        // Then
        #expect(request.blockID == b)
        #expect(request.text == "Body")
        #expect(inputDescriptor.selectedRange == TextRange.point(2))
        #expect(inputDescriptor.focusOffset == 2)
        #expect(inputDescriptor.renderDescriptor.frame == EditorRect(x: 12, y: 13, width: 120, height: 9))
    }
}
