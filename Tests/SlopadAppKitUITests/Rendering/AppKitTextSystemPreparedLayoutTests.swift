#if SLOPAD_BENCHMARK_INSTRUMENTATION
    import AppKit
    import Testing

    import SlopadEngine
    @testable import SlopadAppKitUI

    @MainActor
    @Suite("AppKit text system prepared layout 재사용")
    struct AppKitTextSystemPreparedLayoutTests {
        @Test("production 조립은 renderer와 layouter에 하나의 prepared state를 제공한다")
        func productionCompositionSharesPreparedState() throws {
            // Given
            let system = AppKitTextSystem(style: AppKitEditorStyle())
            let request = BlockMeasureRequest(
                blockID: "block",
                text: "Body text",
                kind: .paragraph,
                availableWidth: 320,
                depth: 0
            )
            let context = try #require(makeBitmapContext())

            // When
            system.textRenderer.draw(
                request,
                in: CGRect(x: 0, y: 0, width: 320, height: 120),
                context: context
            )
            _ = system.textLayouter.caretRect(
                for: TextPosition(blockID: request.blockID, offset: 2),
                in: request
            )

            // Then: identity는 production 조립을, counter는 same-key 재사용을 고정한다.
            #expect(
                system.textLayouter.layoutContextIdentifierForInstrumentation
                    == system.textRenderer.layoutContextIdentifierForInstrumentation
            )
            let counts = system.textLayouter.contextPreparedLayoutCounts
            #expect(counts.prepares == 1)
            #expect(counts.attributedStringBuilds == 1)
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
#endif
