import Foundation
import SlopadEditorCoreModel
import Testing

@Suite("custom block 높이 seam")
struct CustomBlockMeasuringTests {
    private struct FixedHeightMeasurer: BlockMeasuring {
        let height: Double
        func measure(_ request: BlockMeasureRequest) -> BlockMeasurement {
            BlockMeasurement(height: height)
        }
    }

    private struct StubSizing: CustomBlockSizing {
        let handledTypeID: String
        let answer: Double?

        func height(
            typeID: String,
            version: Int,
            payload: Data,
            availableWidth: Double,
            depth: Int
        ) -> Double? {
            guard typeID == handledTypeID else { return nil }
            return answer
        }
    }

    private func request(
        kind: BlockKind,
        availableWidth: Double = 400,
        depth: Int = 0
    ) -> BlockMeasureRequest {
        BlockMeasureRequest(
            blockID: "block",
            text: "",
            kind: kind,
            availableWidth: availableWidth,
            depth: depth
        )
    }

    private static let customKind = BlockKind.custom(
        typeID: "app.todo",
        version: 1,
        payload: Data("{}".utf8)
    )

    @Test("텍스트 블록은 그대로 기존 backend가 답한다")
    func delegatesNonCustomBlocks() {
        // Given
        let measurer = CustomBlockMeasuring(
            base: FixedHeightMeasurer(height: 21),
            sizing: StubSizing(handledTypeID: "app.todo", answer: 99)
        )

        // When / Then
        #expect(measurer.measure(request(kind: .paragraph)).height == 21)
        #expect(measurer.measure(request(kind: .divider)).height == 21)
    }

    @Test("등록된 custom 타입은 host sizer가 답한다")
    func usesHostSizerForRegisteredType() {
        // Given
        let measurer = CustomBlockMeasuring(
            base: FixedHeightMeasurer(height: 21),
            sizing: StubSizing(handledTypeID: "app.todo", answer: 88)
        )

        // When / Then
        #expect(measurer.measure(request(kind: Self.customKind)).height == 88)
    }

    @Test("미등록 타입은 placeholder 높이를 받아 선택 가능한 행으로 남는다")
    func fallsBackToPlaceholderForUnregisteredType() {
        // Given
        let measurer = CustomBlockMeasuring(
            base: FixedHeightMeasurer(height: 21),
            sizing: StubSizing(handledTypeID: "app.other", answer: 88)
        )

        // When / Then
        #expect(
            measurer.measure(request(kind: Self.customKind)).height
                == CustomBlockMeasuring.unsupportedPlaceholderHeight
        )
        #expect(CustomBlockMeasuring.unsupportedPlaceholderHeight > 0)
    }

    @Test("sizer가 아예 없어도 custom block은 placeholder로 측정된다")
    func handlesMissingSizer() {
        // Given
        let measurer = CustomBlockMeasuring(base: FixedHeightMeasurer(height: 21), sizing: nil)

        // When / Then
        #expect(
            measurer.measure(request(kind: Self.customKind)).height
                == CustomBlockMeasuring.unsupportedPlaceholderHeight
        )
    }

    @Test("비유한값과 음수 높이는 height index를 오염시키지 않고 placeholder로 되돌린다")
    func rejectsNonsenseHeights() {
        // Given
        let nonsense: [Double] = [.nan, .infinity, -.infinity, -1]

        // When / Then
        for answer in nonsense {
            let measurer = CustomBlockMeasuring(
                base: FixedHeightMeasurer(height: 21),
                sizing: StubSizing(handledTypeID: "app.todo", answer: answer)
            )
            #expect(
                measurer.measure(request(kind: Self.customKind)).height
                    == CustomBlockMeasuring.unsupportedPlaceholderHeight
            )
        }
    }

    @Test("0 높이는 정상 답변으로 받아들인다")
    func acceptsZeroHeight() {
        // Given
        let measurer = CustomBlockMeasuring(
            base: FixedHeightMeasurer(height: 21),
            sizing: StubSizing(handledTypeID: "app.todo", answer: 0)
        )

        // When / Then
        #expect(measurer.measure(request(kind: Self.customKind)).height == 0)
    }

    @Test("sizer는 너비와 깊이를 받아 다른 높이를 낼 수 있다")
    func passesWidthAndDepthThrough() {
        // Given
        struct WidthSensitiveSizing: CustomBlockSizing {
            func height(
                typeID: String,
                version: Int,
                payload: Data,
                availableWidth: Double,
                depth: Int
            ) -> Double? {
                availableWidth / 2 + Double(depth)
            }
        }
        let measurer = CustomBlockMeasuring(
            base: FixedHeightMeasurer(height: 21),
            sizing: WidthSensitiveSizing()
        )

        // When / Then
        #expect(
            measurer.measure(request(kind: Self.customKind, availableWidth: 400, depth: 2))
                .height == 202
        )
        #expect(
            measurer.measure(request(kind: Self.customKind, availableWidth: 200, depth: 0))
                .height == 100
        )
    }
}
