import Foundation
import Testing

import SlopadCoreModel

@Suite("TextPosition 값")
struct TextPositionTests {
    @Test("affinity가 없는 이전 JSON은 downstream caret으로 복원한다")
    func givenLegacyJSONWithoutAffinity_whenDecoded_thenDownstreamIsUsed() throws {
        // Given
        let data = Data(#"{"blockID":{"rawValue":"a"},"offset":3}"#.utf8)

        // When
        let position = try JSONDecoder().decode(TextPosition.self, from: data)

        // Then
        #expect(position == TextPosition(blockID: "a", offset: 3, affinity: .downstream))
    }

    @Test("upstream affinity는 JSON 왕복 시 보존한다")
    func givenUpstreamAffinity_whenRoundTripped_thenAffinityIsPreserved() throws {
        // Given
        let position = TextPosition(blockID: "a", offset: 3, affinity: .upstream)

        // When
        let data = try JSONEncoder().encode(position)
        let decoded = try JSONDecoder().decode(TextPosition.self, from: data)

        // Then
        #expect(decoded == position)
    }
}
