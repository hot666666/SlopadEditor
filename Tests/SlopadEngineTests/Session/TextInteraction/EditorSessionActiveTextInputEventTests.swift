import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 활성 텍스트 입력 이벤트")
struct EditorSessionActiveTextInputEventTests {
    @Test("활성 텍스트 선택 변경 이벤트는 런타임 선택 상태를 갱신한다")
    func handlesActiveTextSelectionChangedEvent() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("Hello", id: blockID))

        // When
        let update = try #require(
            session.handleInput(
                .activeTextSelectionChanged(blockID: blockID, selectedRange: TextRange(1, 4))
            )
        )

        // Then
        #expect(
            update.selection
                == .text(
                    TextSelection(
                        anchor: TextPosition(blockID: blockID, offset: 1),
                        focus: TextPosition(blockID: blockID, offset: 4)
                    )
                )
        )
        #expect(session.activeTextRange() == TextRange(1, 4))
        #expect(session.activeTextPosition()?.offset == 4)
        #expect(update.invalidation.blockIDs.isEmpty)
        #expect(!update.invalidation.layoutGeometryChanged)
    }

    @Test("활성 텍스트 선택 범위가 canonical 본문 밖이면 선택을 변경하지 않는다")
    func rejectsSelectionOutsideCanonicalText() {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Body", id: blockID),
            selection: .caret(blockID: blockID, offset: 2)
        )

        // When
        let update = session.handleInput(
            .activeTextSelectionChanged(
                blockID: blockID,
                selectedRange: TextRange(0, 5)
            )
        )

        // Then
        #expect(update?.selection == .caret(blockID: blockID, offset: 2))
        #expect(session.editorModel.selection == .caret(blockID: blockID, offset: 2))
    }

    @Test("렌더링 스냅샷은 활성 텍스트 입력 descriptor를 포함한다")
    func renderSnapshotIncludesActiveTextInputDescriptor() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hello", id: blockID),
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 4),
                    focus: TextPosition(blockID: blockID, offset: 1, affinity: .upstream)
                )
            ),
            textLayouter: DeterministicBlockTextLayouter(lineHeight: 10, verticalPadding: 2)
        )

        // When
        let snapshot = session.render(in: EditorViewport(width: 240, scrollY: 0, height: 400))

        // Then
        #expect(snapshot.activeTextInput?.selectedRange == TextRange(1, 4))
        #expect(snapshot.activeTextInput?.focusOffset == 1)
        #expect(snapshot.activeTextInput?.focusAffinity == .upstream)
    }

    @Test("prefix shortcut replacement 후 활성 입력 selection은 제거된 marker 뒤가 아니라 0으로 동기화된다")
    func handlesPrefixShortcutSelectionAfterNativeReplacement() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(document: .singleParagraph("", id: blockID))

        // When
        let update = try #require(
            session.handleInput(
                .command(.replaceText(blockID: blockID, range: TextRange.point(0), text: "# "))
            )
        )

        // Then
        #expect(session.document.block(blockID)?.kind == .heading(level: .h1))
        #expect(session.document.block(blockID)?.content.text == "")
        #expect(update.selection == .caret(blockID: blockID, offset: 0))
        #expect(session.activeTextRange() == TextRange.point(0))
    }
}
