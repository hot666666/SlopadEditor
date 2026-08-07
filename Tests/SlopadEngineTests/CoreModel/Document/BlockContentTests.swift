import Foundation
@testable import SlopadCoreModel
import Testing

@Suite("블록 텍스트 콘텐츠")
struct BlockContentTests {
    @Test("겹치는 mark는 같은 identity끼리 병합되고 presentation run은 겹치지 않는다")
    func givenOverlappingMarks_whenNormalized_thenSameIdentitiesMergeAndPresentationRunsDoNotOverlap() {
        // Given
        let content = BlockContent(
            text: "abcd",
            marks: [
                BlockContent.InlineMark(kind: .strong, range: TextRange(0, 2)),
                BlockContent.InlineMark(kind: .strong, range: TextRange(2, 4)),
                BlockContent.InlineMark(kind: .emphasis, range: TextRange(1, 3))
            ]
        )

        // When
        let marks = content.marks
        let inlineRuns = content.inlineRuns

        // Then
        #expect(marks.contains(BlockContent.InlineMark(kind: .strong, range: TextRange(0, 4))))
        #expect(inlineRuns == [
            BlockContent.InlineRun(range: TextRange(0, 1), text: "a", marks: [.strong]),
            BlockContent.InlineRun(range: TextRange(1, 3), text: "bc", marks: [.strong, .emphasis]),
            BlockContent.InlineRun(range: TextRange(3, 4), text: "d", marks: [.strong])
        ])
    }

    @Test("내부 content revision은 public equality와 Codable schema에 노출되지 않는다")
    func givenDifferentInternalRevisions_whenComparedAndEncoded_thenPublicContentIsStable() throws {
        // Given
        let first = BlockContent(text: "abc", marks: [], revision: 1)
        let second = BlockContent(text: "abc", marks: [], revision: 2)

        // When
        let encoded = try JSONEncoder().encode(first)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let decoded = try JSONDecoder().decode(BlockContent.self, from: encoded)

        // Then
        #expect(first == second)
        #expect(object["revision"] == nil)
        #expect(decoded == first)
        #expect(decoded.revision == 0)
    }
}
