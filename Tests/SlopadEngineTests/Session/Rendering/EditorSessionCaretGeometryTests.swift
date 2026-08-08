import SlopadCoreModel
import Testing

@testable import SlopadEngine

// MARK: - Session-published caret geometry

@Suite("Session 이 발행하는 caret 기하")
struct EditorSessionCaretGeometryTests {
    @Test("활성 입력 서술자가 caret 사각형을 문서 좌표로 싣는다")
    func publishesCaretRect() {
        // Given
        let session = makeSession(text: "Body", caretAt: 2)

        // When
        let snapshot = session.render(in: viewport)

        // Then: 어댑터가 백엔드에 다시 묻지 않고 그릴 수 있어야 한다.
        let descriptor = snapshot.activeTextInput
        #expect(descriptor != nil)
        #expect(descriptor?.caretRect != nil)
    }

    @Test("caret만 있으면 선택 사각형은 비어 있다")
    func caretOnlyHasNoSelectionRects() {
        // Given
        let session = makeSession(text: "Body", caretAt: 2)

        // When
        let snapshot = session.render(in: viewport)

        // Then
        #expect(snapshot.activeTextInput?.selectionRects.isEmpty == true)
    }

    @Test("범위를 선택하면 선택 사각형이 실린다")
    func publishesSelectionRects() {
        // Given
        let blockID: BlockID = "block"
        let session = EditorSession(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "Body"))],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 0),
                    focus: TextPosition(blockID: blockID, offset: 4)
                )),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let snapshot = session.render(in: viewport)

        // Then
        #expect(snapshot.activeTextInput?.selectionRects.isEmpty == false)
    }

    @Test("caret 사각형이 블록 프레임을 따라 이동한다")
    func caretRectFollowsTheBlockFrame() {
        // Given: 두 번째 블록의 caret 은 첫 블록 아래에 있어야 한다 — 문서 좌표라는 뜻이다.
        let first: BlockID = "a"
        let second: BlockID = "b"
        let session = EditorSession(
            blocks: [
                EditorBlockInput(id: first, content: BlockContent(text: "First")),
                EditorBlockInput(id: second, content: BlockContent(text: "Second")),
            ],
            selection: .caret(blockID: second, offset: 0),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let snapshot = session.render(in: viewport)
        let firstFrame = snapshot.visibleBlocks.first { $0.id == first }?.frame

        // Then
        let caret = snapshot.activeTextInput?.caretRect
        #expect(caret != nil)
        #expect((caret?.y ?? 0) >= (firstFrame?.y ?? 0) + (firstFrame?.height ?? 0) - 1)
    }

    @Test("줄 조각 사각형을 문서 좌표로 질의할 수 있다")
    func exposesLineFragmentRects() {
        // Given: 어댑터가 "이 점이 텍스트에 닿는가"를 백엔드 없이 물을 수 있어야 한다.
        let session = makeSession(text: "Body", caretAt: 0)
        let snapshot = session.render(in: viewport)
        let rendered = try? #require(snapshot.visibleBlocks.first)

        // When
        let rects = rendered.map { session.textLineFragmentRects(in: $0.textRender) } ?? []

        // Then
        #expect(!rects.isEmpty)
        #expect(rects.allSatisfy { $0.height > 0 })
    }

    // MARK: - Support

    private let viewport = EditorViewport(width: 240, scrollY: 0, height: 400)

    private func makeSession(text: String, caretAt offset: Int) -> EditorSession {
        EditorSession(
            blocks: [EditorBlockInput(id: "block", content: BlockContent(text: text))],
            selection: .caret(blockID: "block", offset: offset),
            textLayouter: DeterministicBlockTextLayouter()
        )
    }
}
