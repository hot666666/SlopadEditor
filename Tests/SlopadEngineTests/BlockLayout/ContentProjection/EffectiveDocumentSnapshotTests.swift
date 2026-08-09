import Testing

@testable import SlopadBlockLayout
import SlopadCoreModel

@Suite("유효 문서 스냅샷")
struct EffectiveDocumentSnapshotTests {
    @Test("조합이 없으면 snapshot revision의 composition revision은 none이다")
    func givenNoComposition_whenSnapshotRevisionIsRead_thenCompositionRevisionIsNone() {
        // Given
        let document = Document.singleParagraph("Hello", id: "a")

        // When
        let snapshot = EffectiveDocumentSnapshot(document: document)

        // Then
        #expect(snapshot.compositionRevision == 0)
        #expect(snapshot.revision == document.revision)
    }

    @Test("텍스트 조합이 있으면 유효 스냅샷은 임시 텍스트를 반영하고 원본 문서는 바꾸지 않는다")
    func givenTextComposition_whenEffectiveSnapshotIsMeasured_thenCanonicalDocumentIsUnchanged()
        throws
    {
        // Given
        let blockID: BlockID = "a"
        let document = Document.singleParagraph("Hello", id: blockID)
        let composition = TextComposition(
            blockID: blockID,
            replacementRange: TextRange.point(5),
            text: "!",
            revision: 1
        )
        let snapshot = EffectiveDocumentSnapshot(document: document, composition: composition)

        // When
        let effectiveBlock = try #require(snapshot.block(for: blockID))

        // Then
        #expect(effectiveBlock.content.text == "Hello!")
        #expect(snapshot.compositionRevision == 1)
        #expect(document.blocks[blockID]?.content.text == "Hello")
    }

    @Test(
        "replacement 조합이 있으면 block 조회 결과에 임시 텍스트가 포함된다"
    )
    func givenReplacementComposition_whenBlockIsRequested_thenReturnedBlockIncludesTemporaryText()
        throws
    {
        // Given
        let blockID: BlockID = "a"
        let document = Document.singleParagraph("Hello", id: blockID)
        let composition = TextComposition(
            blockID: blockID,
            replacementRange: TextRange(1, 4),
            text: "ey",
            revision: 2
        )
        let snapshot = EffectiveDocumentSnapshot(document: document, composition: composition)

        // When
        let block = try #require(snapshot.block(for: blockID))

        // Then
        #expect(block.content.text == "Heyo")
        #expect(document.blocks[blockID]?.content.text == "Hello")
    }

    @Test(
        "다른 블록의 조합이 있으면 현재 블록 content 조회는 원본 content를 반환한다"
    )
    func givenCompositionForAnotherBlock_whenContentIsRequested_thenCanonicalContentIsReturned()
        throws
    {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let document = makeFlatDocument([
            Block(id: a, content: BlockContent(text: "A")),
            Block(id: b, content: BlockContent(text: "B")),
        ])
        let composition = TextComposition(
            blockID: b,
            replacementRange: TextRange.point(1),
            text: "!",
            revision: 3
        )
        let snapshot = EffectiveDocumentSnapshot(document: document, composition: composition)

        // When
        let canonicalBlock = try #require(snapshot.block(for: a))
        let effectiveBlock = try #require(snapshot.block(for: b))

        // Then
        #expect(canonicalBlock.content.text == "A")
        #expect(effectiveBlock.content.text == "B!")
    }

    @Test("없는 블록의 content를 요청하면 nil을 반환한다")
    func givenMissingBlock_whenContentIsRequested_thenNilIsReturned() {
        // Given
        let snapshot = EffectiveDocumentSnapshot(document: .singleParagraph("Hello", id: "a"))

        // When
        let missingBlock = snapshot.block(for: "missing")

        // Then
        #expect(missingBlock == nil)
    }
}
