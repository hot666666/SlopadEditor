import CoreGraphics
import SlopadCoreModel
import Testing

@testable import SlopadAppKitTextKit

// MARK: - Prepared layout reuse

@Suite("prepared layout 재사용")
struct TextKitPreparedLayoutTests {
    @Test("renderer가 그린 요청을 layouter가 같은 geometry로 이어받는다")
    func rendererThenLayouterUsesCoherentGeometry() throws {
        // Given
        let system = TextKitTextSystem()
        let request = makeRequest(text: "Body text")
        let context = try #require(makeBitmapContext())

        // When
        system.renderer.draw(
            request,
            in: CGRect(x: 0, y: 0, width: 320, height: 120),
            context: context
        )
        let caret = system.layouter.caretRect(
            for: TextPosition(blockID: request.blockID, offset: 2), in: request)

        // Then
        #expect(caret != nil)
        #expect(system.layouter.measure(request).height > 0)
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

    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        @Test("renderer 다음의 같은 layouter 요청은 TextKit을 다시 준비하지 않는다")
        func rendererThenLayouterReusesOnePreparedState() throws {
            // Given
            let system = TextKitTextSystem()
            let request = makeRequest(text: "Body text")
            let context = try #require(makeBitmapContext())

            // When
            system.renderer.draw(
                request,
                in: CGRect(x: 0, y: 0, width: 320, height: 120),
                context: context
            )
            _ = system.layouter.caretRect(
                for: TextPosition(blockID: request.blockID, offset: 2),
                in: request
            )

            // Then: identity는 조립을, counter는 same-key 재사용을 각각 고정한다.
            #expect(
                system.layouter.layoutContextIdentifierForInstrumentation
                    == system.renderer.layoutContextIdentifierForInstrumentation
            )
            let counts = system.layouter.contextPreparedLayoutCounts
            #expect(counts.prepares == 1)
            #expect(counts.attributedStringBuilds == 1)
        }
    #endif

    // MARK: - Support

    private func makeRequest(blockID: BlockID = "block", text: String) -> BlockMeasureRequest {
        BlockMeasureRequest(
            blockID: blockID, text: text, kind: .paragraph, availableWidth: 320, depth: 0)
    }

    private func makeBitmapContext() -> CGContext? {
        let width = 640
        let height = 240
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
