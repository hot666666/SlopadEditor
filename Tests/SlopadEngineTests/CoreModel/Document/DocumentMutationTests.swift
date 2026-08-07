@testable import SlopadCoreModel
import Testing

@Suite("문서 변경")
struct DocumentMutationTests {
    @Test("공개 문서 변경 API로 구조 작업을 실행해도 불변식은 유지된다")
    func givenPublicDocumentMutationAPI_whenStructuralOperationsRun_thenInvariantsStayValid() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        var document = Document()
        try document.insertBlock(Block(id: a, content: BlockContent(text: "Alpha"))).get()
        try document.insertBlock(Block(id: b, content: BlockContent(text: "Beta"))).get()
        try document.insertBlock(Block(id: c, content: BlockContent(text: "Child")), parentID: b).get()
        let isInitialDocumentValid = document.validateInvariants().isValid

        // When
        let split = try document.splitBlock(blockID: b, offset: 2, newBlockID: "b2").get()
        let isValidAfterSplit = document.validateInvariants().isValid
        _ = try document.mergeBlocks(target: a, source: b).get()
        let isValidAfterMerge = document.validateInvariants().isValid
        try document.moveSubtreeRange(["b2"], toParentID: a, index: 0).get()
        let isValidAfterChildMove = document.validateInvariants().isValid
        try document.moveSubtreeRange(["b2"], toParentID: nil, index: 1).get()
        let isValidAfterRootMove = document.validateInvariants().isValid

        // Then
        #expect(isInitialDocumentValid)
        #expect(split.transferredChildIDs == [c])
        #expect(isValidAfterSplit)
        #expect(isValidAfterMerge)
        #expect(isValidAfterChildMove)
        #expect(isValidAfterRootMove)
    }

    @Test("mark가 있는 블록을 분할하면 mark가 양쪽에 분배된다")
    func givenSplitBlockWithMarkedContent_whenSplit_thenMarksAreAssignedToEachSide() throws {
        // Given
        let blockID: BlockID = "a"
        var document = Document.singleParagraph(
            "abcd",
            id: blockID
        )
        try document.replaceContent(
            blockID: blockID,
            content: BlockContent(text: "abcd", marks: [BlockContent.InlineMark(kind: .strong, range: TextRange(1, 3))])
        ).get()

        // When
        let split = try document.splitBlock(blockID: blockID, offset: 2, newBlockID: "b").get()

        // Then
        #expect(split.splitOffset == 2)
        #expect(document.blocks[blockID]?.content.text == "ab")
        #expect(document.blocks[blockID]?.content.marks == [BlockContent.InlineMark(kind: .strong, range: TextRange(1, 2))])
        #expect(document.blocks["b"]?.content.text == "cd")
        #expect(document.blocks["b"]?.content.marks == [BlockContent.InlineMark(kind: .strong, range: TextRange(0, 1))])
    }

    @Test("descendant 아래로 이동을 요청하면 cycle 생성이 거부된다")
    func givenMoveUnderDescendant_whenRequested_thenCycleIsRejected() throws {
        // Given
        let root: BlockID = "root"
        let child: BlockID = "child"
        var document = Document.singleParagraph("root", id: root)
        document.appendChild(Block(id: child), to: root)

        // When
        let result = document.moveSubtreeRange([root], toParentID: child, index: 0)

        // Then
        switch result {
        case .failure(.wouldCreateCycle(root)):
            break

        default:
            Issue.record("descendant 아래 이동은 cycle 실패로 반환되어야 한다")
        }
        #expect(document.validateInvariants().isValid)
    }
}
