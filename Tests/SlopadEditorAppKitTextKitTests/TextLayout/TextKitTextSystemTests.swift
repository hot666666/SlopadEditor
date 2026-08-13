import Testing

@testable import SlopadEditorAppKitTextKit

@Suite("TextKit text system 조립")
struct TextKitTextSystemTests {
    @Test("layouter와 renderer는 하나의 layout context를 공유한다")
    func layouterAndRendererShareLayoutContext() {
        // Given
        let system = TextKitTextSystem()

        // When
        let layouterContext = system.layouter.layoutContextIdentifierForTesting
        let rendererContext = system.renderer.layoutContextIdentifierForTesting

        // Then
        #expect(layouterContext == rendererContext)
    }
}
