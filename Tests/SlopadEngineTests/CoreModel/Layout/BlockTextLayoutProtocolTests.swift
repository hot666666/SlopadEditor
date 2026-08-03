import Testing

import SlopadCoreModel

@Suite("블록 텍스트 레이아웃 프로토콜")
struct BlockTextLayoutProtocolTests {
    @Test("legacy textPosition backend는 기본 hit-test 결과로 감싼다")
    func defaultHitTestWrapsLegacyPosition() throws {
        // Given
        let layouter: any BlockTextLayoutProtocol = DeterministicBlockTextLayouter()
        let request = BlockMeasureRequest(
            blockID: "block",
            text: "Body",
            kind: .paragraph,
            availableWidth: 240,
            depth: 0
        )
        let point = EditorPoint(x: 16, y: 5)
        let legacyPosition = layouter.textPosition(at: point, in: request)

        // When
        let result = try #require(layouter.textHitTest(at: point, in: request))

        // Then
        #expect(result.position == legacyPosition)
        #expect(result.navigationContext == nil)
    }
}
