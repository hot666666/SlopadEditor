import SlopadEditorCoreModel
import Testing

@testable import SlopadEditorBlockLayout

// MARK: - BlockLayout Capability

/// Implements measurement and nothing else.
///
/// This is the point of the test: if `BlockLayout` ever reaches for caret geometry, word
/// boundaries, or a deletion range, this type stops satisfying it and the package fails to
/// compile. A runtime assertion could not catch that — the contract is the check.
private struct MeasureOnlyLayouter: BlockMeasuring {
    func measure(_ request: BlockMeasureRequest) -> BlockMeasurement {
        BlockMeasurement(height: Double(request.text.count) + 1, firstBaseline: 1)
    }
}

@Suite("BlockLayout 계약 폭")
struct BlockLayoutCapabilityTests {
    @Test("BlockLayout은 측정 계약만으로 전체 레이아웃을 수행한다")
    func laysOutWithMeasurementAlone() {
        // Given
        var blockLayout = BlockLayout()
        let document = Document(blockInputs: [
            EditorBlockInput(id: "a", content: BlockContent(text: "hello")),
            EditorBlockInput(id: "b", content: BlockContent(text: "world!")),
        ])
        let input = makeBlockLayoutTestInput(document: document, availableWidth: 320)

        // When
        _ = runBlockLayoutPass(&blockLayout, input: input, textLayouter: MeasureOnlyLayouter())

        // Then
        #expect(blockLayout.totalHeight > 0)
    }

    @Test("측정만 구현한 백엔드가 내용 길이에 따라 다른 높이를 만든다")
    func reflectsMeasurementChanges() {
        // Given: 각각 별도의 BlockLayout 을 쓴다. 하나를 재사용하면 measurement cache 가
        // block.content.revision 으로 키를 잡기 때문에, 같은 ID·같은 revision 을 가진 다른
        // 문서를 넣어도 이전 측정값이 돌아온다. 프로덕션은 문서 교체 시 BlockLayout 자체를
        // 새로 만들어 이 상황을 만들지 않는다.
        func height(of text: String) -> Double {
            var blockLayout = BlockLayout()
            let document = Document(blockInputs: [
                EditorBlockInput(id: "a", content: BlockContent(text: text))
            ])
            _ = runBlockLayoutPass(
                &blockLayout,
                input: makeBlockLayoutTestInput(document: document, availableWidth: 320),
                textLayouter: MeasureOnlyLayouter()
            )
            return blockLayout.totalHeight
        }

        // When / Then
        #expect(height(of: "much longer text") > height(of: "hi"))
    }
}
