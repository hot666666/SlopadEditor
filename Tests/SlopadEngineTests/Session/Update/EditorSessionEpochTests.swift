import Testing

@testable import SlopadEngine
import SlopadCoreModel

@Suite("에디터 세션 epoch")
struct EditorSessionEpochTests {
    @Test("같은 세션에서 반복해 읽은 epoch은 동일하다")
    func epochIsStableWithinOneSession() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: DeterministicBlockTextLayouter()
        )
        let initial = session.documentSnapshot.epoch

        // When
        _ = try #require(session.handleInput(.command(.insertText("!"))))

        // Then
        #expect(session.documentSnapshot.epoch == initial)
    }

    @Test("세션이 교체되면 revision은 0으로 되감기지만 epoch은 달라진다")
    func epochDistinguishesSessionsThatShareARevision() throws {
        // Given
        let blockID: BlockID = "a"
        let first = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: DeterministicBlockTextLayouter()
        )
        _ = try #require(first.handleInput(.command(.insertText("!"))))
        let captured = first.documentSnapshot

        // When: 호스트가 위 스냅샷을 들고 있는 동안 문서가 교체된다.
        let replacement = EditorSession(
            document: .singleParagraph("B", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: DeterministicBlockTextLayouter()
        )
        _ = try #require(replacement.handleInput(.command(.insertText("?"))))
        let current = replacement.documentSnapshot

        // Then: revision만으로는 두 세션을 구분할 수 없다. 이것이 epoch이 필요한 이유다.
        #expect(captured.revision == current.revision)
        #expect(captured.epoch != current.epoch)
    }

    @Test("committed update의 epoch은 그 시점 documentSnapshot의 epoch과 같다")
    func updateCarriesTheSameEpochAsTheSnapshot() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When
        let update = try #require(session.handleInput(.command(.insertText("!"))))

        // Then
        #expect(update.committedDocumentRevision != nil)
        #expect(update.epoch == session.documentSnapshot.epoch)
    }

    @Test("committed가 아닌 update도 epoch을 싣는다")
    func nonCommittedUpdateStillCarriesEpoch() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hi", id: blockID),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When: 조합 시작은 canonical 문서를 커밋하지 않는다.
        let update = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: blockID,
                    replacementRange: TextRange.point(2),
                    text: "!"
                )
            )
        )

        // Then
        #expect(update.committedDocumentRevision == nil)
        #expect(update.epoch == session.documentSnapshot.epoch)
    }

    @Test("IME 조합 중에도 documentSnapshot은 throw 없이 epoch을 준다")
    func snapshotStaysReadableDuringComposition() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hi", id: blockID),
            textLayouter: DeterministicBlockTextLayouter()
        )
        let beforeComposition = session.documentSnapshot.epoch

        // When
        _ = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: blockID,
                    replacementRange: TextRange.point(2),
                    text: "!"
                )
            )
        )

        // Then: persistence 호스트가 정확히 이 시점에 알고 싶어 하는 값이다.
        #expect(session.composition != nil)
        #expect(session.documentSnapshot.epoch == beforeComposition)
        #expect(session.documentSnapshot.blocks.first?.content.text == "Hi")
    }

    @Test("조합 중 documentContextSnapshot은 기존대로 거절한다")
    func contextSnapshotStillRefusesDuringComposition() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("Hi", id: blockID),
            selection: .caret(blockID: blockID, offset: 2),
            textLayouter: DeterministicBlockTextLayouter()
        )
        _ = try #require(
            session.handleInput(
                .beginComposition(
                    blockID: blockID,
                    replacementRange: TextRange.point(2),
                    text: "!"
                )
            )
        )

        // When / Then: 약한 토큰이 생겼다고 해서 강한 CAS 토큰이 느슨해지지 않는다.
        #expect(throws: EditorDocumentTransactionError.activeComposition) {
            try session.documentContextSnapshot()
        }
    }

    @Test("patch CAS 토큰은 세션 epoch을 계속 고정한다")
    func patchSourceStillPinsTheSession() throws {
        // Given
        let blockID: BlockID = "a"
        let session = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: DeterministicBlockTextLayouter()
        )
        let context = try session.documentContextSnapshot()

        let otherSession = EditorSession(
            document: .singleParagraph("A", id: blockID),
            selection: .caret(blockID: blockID, offset: 1),
            textLayouter: DeterministicBlockTextLayouter()
        )

        // When: 다른 세션에서 뜬 토큰으로 patch를 시도한다.
        let foreignPatch = EditorDocumentPatch(
            source: try otherSession.documentContextSnapshot().source,
            replacementBlocks: [
                EditorBlockInput(id: blockID, content: BlockContent(text: "Z"))
            ],
            selectionAfter: .caret(blockID: blockID, offset: 1)
        )

        // Then
        #expect(throws: EditorDocumentTransactionError.staleSource) {
            try session.applyDocumentPatch(foreignPatch)
        }
        #expect(context.source == context.source)
        #expect(session.documentSnapshot.blocks.first?.content.text == "A")
    }
}
