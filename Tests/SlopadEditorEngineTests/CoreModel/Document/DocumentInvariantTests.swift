@testable import SlopadCoreModel
import Testing

@Suite("문서 불변식")
struct DocumentInvariantTests {
    @Test("유효한 문서를 검증하면 valid report를 반환한다")
    func givenValidDocument_whenInvariantsAreValidated_thenReportIsValid() {
        // Given
        let root: BlockID = "root"
        let child: BlockID = "child"
        var document = Document.singleParagraph("root", id: root)
        document.appendChild(Block(id: child, content: BlockContent(text: "child")), to: root)

        // When
        let report = document.validateInvariants()

        // Then
        #expect(report.isValid)
        #expect(document.rootBlockIDs == [root])
        #expect(document.children(of: root) == [child])
    }

    @Test("깨진 문서를 검증하면 구체적인 invariant error를 반환한다")
    func givenBrokenDocuments_whenInvariantsAreValidated_thenSpecificErrorsAreReported() {
        // Given
        let root: BlockID = "root"
        let child: BlockID = "child"
        let missing: BlockID = "missing"
        let orphan: BlockID = "orphan"

        let invalidRootParent = Document.unsafeForInvariantTesting(
            rootBlockIDs: [root],
            blocks: [root: Block(id: root, parentID: child)]
        )

        let missingReference = Document.unsafeForInvariantTesting(
            rootBlockIDs: [root],
            blocks: [root: Block(id: root, childIDs: [missing])]
        )

        let duplicateChild = Document.unsafeForInvariantTesting(
            rootBlockIDs: [root],
            blocks: [
                root: Block(id: root, childIDs: [child, child]),
                child: Block(id: child, parentID: root)
            ]
        )

        let mismatch = Document.unsafeForInvariantTesting(
            rootBlockIDs: [root],
            blocks: [
                root: Block(id: root, childIDs: [child]),
                child: Block(id: child, parentID: nil)
            ]
        )

        let orphaned = Document.unsafeForInvariantTesting(
            rootBlockIDs: [root],
            blocks: [
                root: Block(id: root),
                orphan: Block(id: orphan)
            ]
        )

        let cycle = Document.unsafeForInvariantTesting(
            rootBlockIDs: [root],
            blocks: [
                root: Block(id: root, childIDs: [child]),
                child: Block(id: child, parentID: root, childIDs: [root])
            ]
        )

        let duplicateRoot = Document.unsafeForInvariantTesting(
            rootBlockIDs: [root, root],
            blocks: [root: Block(id: root)]
        )

        // When
        let invalidRootParentViolations = invalidRootParent.validateInvariants().violations
        let missingReferenceViolations = missingReference.validateInvariants().violations
        let duplicateChildViolations = duplicateChild.validateInvariants().violations
        let mismatchViolations = mismatch.validateInvariants().violations
        let orphanedViolations = orphaned.validateInvariants().violations
        let cycleViolations = cycle.validateInvariants().violations
        let duplicateRootViolations = duplicateRoot.validateInvariants().violations

        // Then
        #expect(invalidRootParentViolations.contains(.invalidRootParent(root, actualParent: child)))
        #expect(missingReferenceViolations.contains(.missingBlockReference(parent: root, child: missing)))
        #expect(duplicateChildViolations.contains(.duplicateChild(parent: root, child: child)))
        #expect(mismatchViolations.contains(.parentChildMismatch(parent: root, child: child, actualParent: nil)))
        #expect(orphanedViolations.contains(.orphan(orphan)))
        #expect(cycleViolations.contains(.cycleDetected(root)))
        #expect(duplicateRootViolations.contains(.visibleSequenceMismatch(expected: [root, root], actual: [root])))
    }
}

private extension Document {
    static func unsafeForInvariantTesting(
        rootBlockIDs: [BlockID],
        blocks: [BlockID: Block],
        revision: Int = 0
    ) -> Document {
        Document(uncheckedRootBlockIDs: rootBlockIDs, blocks: blocks, revision: revision)
    }
}
