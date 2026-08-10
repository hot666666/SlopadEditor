import SlopadCoreModel
import Testing

@Suite("selection-independent canonical document input validation")
struct CanonicalDocumentInputTests {
    @Test("selection 없이 canonical DFS input만 검증한다")
    func validatesCanonicalInputWithoutSelection() throws {
        // Given
        let blocks = [
            EditorBlockInput(id: "root"),
            EditorBlockInput(id: "child", parentID: "root"),
            EditorBlockInput(id: "second-root"),
        ]

        // When / Then
        try CanonicalDocumentInput.validate(blocks)
    }

    @Test("여섯 document invariant는 shared seam에서 fail closed 한다")
    func rejectsEveryDocumentInputInvariant() {
        // Given
        var invalidContent = BlockContent(text: "abcd")
        invalidContent.marks = [
            .init(kind: .strong, range: TextRange(2, 4)),
            .init(kind: .emphasis, range: TextRange(0, 1)),
        ]

        // When / Then
        #expect(throws: CanonicalDocumentInputValidationError.emptyDocument) {
            try CanonicalDocumentInput.validate([])
        }
        #expect(throws: CanonicalDocumentInputValidationError.duplicateBlockID("a")) {
            try CanonicalDocumentInput.validate([
                EditorBlockInput(id: "a"),
                EditorBlockInput(id: "a"),
            ])
        }
        #expect(throws: CanonicalDocumentInputValidationError.invalidContent(blockID: "a")) {
            try CanonicalDocumentInput.validate([
                EditorBlockInput(id: "a", content: invalidContent)
            ])
        }
        #expect(
            throws: CanonicalDocumentInputValidationError.missingParent(
                blockID: "a",
                parentID: "missing"
            )
        ) {
            try CanonicalDocumentInput.validate([
                EditorBlockInput(id: "a", parentID: "missing")
            ])
        }
        #expect(throws: CanonicalDocumentInputValidationError.cycleDetected("a")) {
            try CanonicalDocumentInput.validate([
                EditorBlockInput(id: "a", parentID: "b"),
                EditorBlockInput(id: "b", parentID: "a"),
            ])
        }
        #expect(throws: CanonicalDocumentInputValidationError.noncanonicalDepthFirstOrder) {
            try CanonicalDocumentInput.validate([
                EditorBlockInput(id: "a"),
                EditorBlockInput(id: "b"),
                EditorBlockInput(id: "child", parentID: "a"),
            ])
        }
    }
}
