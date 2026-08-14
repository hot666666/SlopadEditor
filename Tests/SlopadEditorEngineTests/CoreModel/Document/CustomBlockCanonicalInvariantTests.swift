import Foundation
import SlopadEditorCoreModel
import Testing

@Suite("host custom block canonical invariants")
struct CustomBlockCanonicalInvariantTests {
    private static func customKind(
        typeID: String = "app.todo",
        version: Int = 1,
        payload: Data = Data("{}".utf8)
    ) -> BlockKind {
        .custom(typeID: typeID, version: version, payload: payload)
    }

    @Test("payload와 typeID를 갖춘 leaf custom block은 canonical input을 통과한다")
    func acceptsWellFormedCustomLeaf() throws {
        // Given
        let blocks = [
            EditorBlockInput(id: "paragraph"),
            EditorBlockInput(id: "custom", kind: Self.customKind()),
        ]

        // When / Then
        try CanonicalDocumentInput.validate(blocks)
    }

    @Test("빈 typeID는 provider로 라우팅될 수 없으므로 거부한다")
    func rejectsEmptyTypeID() {
        // Given
        let blocks = [EditorBlockInput(id: "custom", kind: Self.customKind(typeID: ""))]

        // When / Then
        #expect(throws: CanonicalDocumentInputValidationError.customTypeIDEmpty("custom")) {
            try CanonicalDocumentInput.validate(blocks)
        }
    }

    @Test("payload 예산 경계는 통과하고 경계 + 1은 거부한다")
    func rejectsPayloadOnlyAboveLimit() throws {
        // Given
        let limit = BlockKind.customPayloadByteLimit
        let atLimit = EditorBlockInput(
            id: "custom",
            kind: Self.customKind(payload: Data(repeating: 0x61, count: limit))
        )
        let aboveLimit = EditorBlockInput(
            id: "custom",
            kind: Self.customKind(payload: Data(repeating: 0x61, count: limit + 1))
        )

        // When / Then
        try CanonicalDocumentInput.validate([atLimit])
        #expect(throws: CanonicalDocumentInputValidationError.customPayloadTooLarge("custom")) {
            try CanonicalDocumentInput.validate([aboveLimit])
        }
    }

    @Test("custom block이 canonical 텍스트나 inline mark를 실으면 거부한다")
    func rejectsCustomBlockCarryingText() {
        // Given
        var markedContent = BlockContent(text: "abcd")
        markedContent.marks = [.init(kind: .strong, range: TextRange(0, 4))]

        let withText = EditorBlockInput(
            id: "custom",
            kind: Self.customKind(),
            content: BlockContent(text: "hello")
        )
        let withMarks = EditorBlockInput(
            id: "custom",
            kind: Self.customKind(),
            content: markedContent
        )

        // When / Then
        #expect(throws: CanonicalDocumentInputValidationError.customBlockCarriesText("custom")) {
            try CanonicalDocumentInput.validate([withText])
        }
        #expect(throws: CanonicalDocumentInputValidationError.customBlockCarriesText("custom")) {
            try CanonicalDocumentInput.validate([withMarks])
        }
    }

    @Test("1차 custom block은 leaf이므로 자식을 가지면 거부한다")
    func rejectsCustomBlockWithChildren() {
        // Given
        let blocks = [
            EditorBlockInput(id: "custom", kind: Self.customKind()),
            EditorBlockInput(id: "child", parentID: "custom"),
        ]

        // When / Then
        #expect(throws: CanonicalDocumentInputValidationError.customBlockHasChildren("custom")) {
            try CanonicalDocumentInput.validate(blocks)
        }
    }

    @Test("custom block은 divider와 같이 텍스트 능력이 없다")
    func customBlockIsNotTextCapable() {
        // Given / When / Then
        #expect(Self.customKind().isCustom)
        #expect(!BlockKind.paragraph.isCustom)
    }

    @Test("payload가 다르면 kind가 달라지므로 측정 캐시 키가 갱신된다")
    func payloadParticipatesInKindEquality() {
        // Given
        let first = Self.customKind(payload: Data("one".utf8))
        let second = Self.customKind(payload: Data("two".utf8))

        // When / Then
        #expect(first != second)
        #expect(first == Self.customKind(payload: Data("one".utf8)))
        #expect(Self.customKind(version: 1) != Self.customKind(version: 2))
    }
}
