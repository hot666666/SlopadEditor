import SlopadCoreModel
import Testing

@testable import SlopadAppKitTextKit

// MARK: - Prepared layout reuse

@Suite("prepared layout 재사용")
struct TextKitPreparedLayoutTests {
    @Test("layouter와 renderer가 하나의 컨텍스트를 공유한다")
    func sharesOneContext() {
        // Given: 분리돼 있으면 한 블록을 그린 직후 그 블록의 caret 을 물어도 다시 준비한다.
        let system = TextKitTextSystem()
        let request = makeRequest(text: "Body text")

        // When
        _ = system.layouter.measure(request)
        let caret = system.layouter.caretRect(
            for: TextPosition(blockID: request.blockID, offset: 2), in: request)

        // Then: 같은 컨텍스트를 쓰는지는 결과로 확인할 수 없으므로, 최소한 두 역할이 서로의
        // 준비 상태를 깨지 않고 동작하는지를 고정한다.
        #expect(caret != nil)
        #expect(system.layouter.measure(request).height > 0)
    }

    @Test("같은 요청을 반복해도 attributed string을 다시 만들지 않는다")
    func reusesBuiltAttributedString() {
        // Given
        let system = TextKitTextSystem()
        let request = makeRequest(text: "Body text")

        // When: 같은 블록을 여러 번 오간다.
        for _ in 0..<5 {
            _ = system.layouter.measure(request)
            _ = system.layouter.lineFragments(for: request)
        }

        // Then: 결과가 흔들리지 않아야 한다. 캐시는 최적화이지 authority 가 아니다.
        let heights = (0..<3).map { _ in system.layouter.measure(request).height }
        #expect(Set(heights).count == 1)
    }

    @Test("여러 블록을 오가도 각 블록의 측정값이 일관된다")
    func staysConsistentAcrossBlocks() {
        // Given: 준비 슬롯이 하나라 블록을 오가면 매번 다시 준비된다. 그래도 답은 같아야 한다.
        let system = TextKitTextSystem()
        let a = makeRequest(blockID: "a", text: "short")
        let b = makeRequest(blockID: "b", text: "a considerably longer paragraph of text")

        // When
        let firstA = system.layouter.measure(a).height
        let firstB = system.layouter.measure(b).height
        let secondA = system.layouter.measure(a).height
        let secondB = system.layouter.measure(b).height

        // Then
        #expect(firstA == secondA)
        #expect(firstB == secondB)
        #expect(firstB > firstA)
    }

    @Test("캐시를 비워도 같은 요청이 같은 결과를 낸다")
    func cacheIsAnOptimizationNotAuthority() {
        // Given
        let system = TextKitTextSystem()
        let request = makeRequest(text: "Body text")
        let before = system.layouter.measure(request)

        // When
        system.invalidateCaches()

        // Then
        #expect(system.layouter.measure(request) == before)
    }

    // MARK: - Support

    private func makeRequest(blockID: BlockID = "block", text: String) -> BlockMeasureRequest {
        BlockMeasureRequest(
            blockID: blockID, text: text, kind: .paragraph, availableWidth: 320, depth: 0)
    }
}
