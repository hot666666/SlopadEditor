import Foundation
import SlopadCoreModel
import Testing

// MARK: - InlineMark.Kind Coding

@Suite("InlineMark.Kind 인코딩")
struct InlineMarkKindCodingTests {
    private static let allKinds: [BlockContent.InlineMark.Kind] = [
        .strong,
        .emphasis,
        .code,
        .strikethrough,
        .link(destination: "https://example.com/a?b=c"),
    ]

    @Test("모든 kind가 라운드트립한다")
    func roundTripsEveryKind() throws {
        for kind in Self.allKinds {
            // Given
            let encoded = try JSONEncoder().encode(kind)

            // When
            let decoded = try JSONDecoder().decode(
                BlockContent.InlineMark.Kind.self, from: encoded)

            // Then
            #expect(decoded == kind)
        }
    }

    @Test("인코딩 형식이 개명 이전과 동일하다")
    func keepsTheEncodedShape() throws {
        // Given
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // When
        let encoded = try Self.allKinds.map {
            String(decoding: try encoder.encode($0), as: UTF8.self)
        }

        // Then: 개명은 case 이름만 바꾼다. 컨테이너 모양은 그대로여야 한다.
        #expect(
            encoded == [
                #"{"strong":{}}"#,
                #"{"emphasis":{}}"#,
                #"{"code":{}}"#,
                #"{"strikethrough":{}}"#,
                #"{"link":{"destination":"https:\/\/example.com\/a?b=c"}}"#,
            ])
    }

    @Test("개명 이전 이름으로 저장된 문서도 디코딩된다")
    func decodesSupersededNames() throws {
        // Given
        let legacy = [
            (json: #"{"bold":{}}"#, expected: BlockContent.InlineMark.Kind.strong),
            (json: #"{"italic":{}}"#, expected: BlockContent.InlineMark.Kind.emphasis),
        ]

        for entry in legacy {
            // When
            let decoded = try JSONDecoder().decode(
                BlockContent.InlineMark.Kind.self, from: Data(entry.json.utf8))

            // Then
            #expect(decoded == entry.expected)
        }
    }

    @Test("개명 이전 이름으로 저장된 블록 문서 전체가 주입된다")
    func decodesSupersededNamesInsideBlockInput() throws {
        // Given: 개명 후 인코딩한 문서에서 mark 이름만 개명 이전으로 되돌린다. 손으로 쓴
        // JSON은 BlockID 같은 주변 타입의 표현까지 고정해버려, 정작 검증하려는 mark 이름과
        // 무관한 이유로 깨진다.
        let block = EditorBlockInput(
            id: "block",
            content: BlockContent(
                text: "abcd",
                marks: [
                    BlockContent.InlineMark(kind: .strong, range: TextRange(0, 2)),
                    BlockContent.InlineMark(kind: .emphasis, range: TextRange(2, 4)),
                ]
            )
        )
        let current = String(decoding: try JSONEncoder().encode([block]), as: UTF8.self)
        let legacy = current
            .replacingOccurrences(of: #""strong":{}"#, with: #""bold":{}"#)
            .replacingOccurrences(of: #""emphasis":{}"#, with: #""italic":{}"#)
        #expect(legacy != current, "치환이 실제로 일어나야 이 테스트가 의미를 갖는다")

        // When
        let decoded = try JSONDecoder().decode([EditorBlockInput].self, from: Data(legacy.utf8))

        // Then
        #expect(decoded == [block])
    }

    @Test("kind가 여러 개거나 비어 있으면 디코딩을 거부한다")
    func rejectsAmbiguousPayloads() {
        // Given
        let invalid = [#"{}"#, #"{"strong":{},"emphasis":{}}"#]

        for json in invalid {
            // When / Then
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(
                    BlockContent.InlineMark.Kind.self, from: Data(json.utf8))
            }
        }
    }
}
