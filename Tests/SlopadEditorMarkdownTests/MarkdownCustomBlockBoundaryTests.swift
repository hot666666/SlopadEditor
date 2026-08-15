import Foundation
import SlopadEditorCoreModel
import SlopadEditorMarkdown
import Testing

@Suite("Markdown custom block 경계")
struct MarkdownCustomBlockBoundaryTests {
    private static let customKind = BlockKind.custom(
        typeID: "app.todo",
        version: 1,
        payload: Data("{\"id\":7}".utf8)
    )

    private func encodingError(_ inputs: [EditorBlockInput]) -> MarkdownEncodingError? {
        do {
            _ = try SlopadEditorMarkdown.encode(inputs)
            return nil
        } catch {
            return error
        }
    }

    @Test("custom block을 만나면 typeID를 지목하며 encode가 실패한다")
    func encodeFailsAndNamesTheType() {
        // Given
        let inputs = [
            EditorBlockInput(id: "intro", content: BlockContent(text: "intro")),
            EditorBlockInput(id: "custom", kind: Self.customKind),
        ]

        // When
        let error = encodingError(inputs)

        // Then
        #expect(
            error?.diagnostics.contains {
                $0.kind == .unsupportedCustomBlock(typeID: "app.todo")
            } == true
        )
        #expect(error?.diagnostics.contains { $0.blockID == "custom" } == true)
    }

    @Test("encode는 부분 결과 없이 실패한다 — 지원 블록만 남긴 Markdown을 만들지 않는다")
    func encodeProducesNoPartialMarkdown() {
        // Given — custom block 앞뒤로 정상 블록이 있다
        let inputs = [
            EditorBlockInput(id: "before", content: BlockContent(text: "before")),
            EditorBlockInput(id: "custom", kind: Self.customKind),
            EditorBlockInput(id: "after", content: BlockContent(text: "after")),
        ]

        // When
        var encoded: String?
        do {
            encoded = try SlopadEditorMarkdown.encode(inputs)
        } catch {
            encoded = nil
        }

        // Then
        #expect(encoded == nil)
    }

    @Test("typeID가 다르면 진단도 그 typeID를 담는다")
    func diagnosticCarriesEachTypeID() {
        // Given
        let inputs = [
            EditorBlockInput(
                id: "chart",
                kind: .custom(typeID: "app.chart", version: 2, payload: Data())
            )
        ]

        // When
        let error = encodingError(inputs)

        // Then
        #expect(
            error?.diagnostics.contains {
                $0.kind == .unsupportedCustomBlock(typeID: "app.chart")
            } == true
        )
    }

    @Test("호스트가 표준 블록으로 미리 변환하면 encode가 통과한다")
    func encodeSucceedsAfterHostSideConversion() throws {
        // Given — 코덱 밖에서 호스트가 자기 블록을 문단으로 바꾼 결과
        let converted = [
            EditorBlockInput(id: "intro", content: BlockContent(text: "intro")),
            EditorBlockInput(id: "custom", content: BlockContent(text: "Todo: 장보기")),
        ]

        // When
        let encoded = try SlopadEditorMarkdown.encode(converted)
        let decoded = try SlopadEditorMarkdown.decode(encoded)

        // Then — 의미로 확인한다. Markdown 이스케이프 세부에 단언을 걸면 코덱이
        // 옳게 동작하는 동안에도 테스트가 깨진다.
        #expect(decoded.map(\.content.text) == ["intro", "Todo: 장보기"])
    }

    @Test("decode는 custom block을 만들 수 없어 왕복이 비대칭이다")
    func decodeCannotProduceCustomBlocks() throws {
        // Given — 호스트 변환을 거친 Markdown
        let markdown = "intro\n\nTodo: 장보기\n"

        // When
        let decoded = try SlopadEditorMarkdown.decode(markdown)

        // Then
        #expect(!decoded.isEmpty)
        #expect(!decoded.contains { $0.kind.isCustom })
    }
}
