import Foundation
import SlopadCoreModel
import Testing

@testable import SlopadEditorArchive

@Suite("SlopadEditor native archive")
struct SlopadEditorArchiveTests {
    @Test("공개 alias는 CoreModel 값과 type identity를 유지한다")
    func publicAliasesAreTypeIdentical() {
        // Given
        let archiveID: BlockID = "same"
        let archiveKind: BlockKind = .heading(level: .h2)
        let archiveRange = TextRange(0, 1)
        let archiveContent = BlockContent(
            text: "x",
            marks: [.init(kind: .strong, range: archiveRange)]
        )
        let archiveInput = EditorBlockInput(
            id: archiveID,
            kind: archiveKind,
            content: archiveContent
        )

        // When
        let coreID: SlopadCoreModel.BlockID = archiveID
        let coreKind: SlopadCoreModel.BlockKind = archiveKind
        let coreContent: SlopadCoreModel.BlockContent = archiveContent
        let coreRange: SlopadCoreModel.TextRange = archiveRange
        let coreInput: SlopadCoreModel.EditorBlockInput = archiveInput

        // Then
        #expect(coreID == archiveID)
        #expect(coreKind == archiveKind)
        #expect(coreContent == archiveContent)
        #expect(coreRange == archiveRange)
        #expect(coreInput == archiveInput)
    }

    @Test("V1 round trip은 ID, tree preorder, kind, content, mark를 모두 보존한다")
    func v1RoundTripPreservesCompleteCanonicalValues() throws {
        // Given
        let root: BlockID = "root"
        let child: BlockID = "child"
        let blocks = allKindBlocks(root: root, child: child)

        // When
        let data = try SlopadEditorArchive.encode(blocks)
        let decoded = try SlopadEditorArchive.decode(data)

        // Then
        #expect(decoded == blocks)
    }

    @Test("Core가 허용하는 empty ID와 associated string 및 escaped Unicode를 보존한다")
    func preservesUnconstrainedCoreStringsAndEscapedUnicode() throws {
        // Given
        let source = Self.json(
            #"{"formatVersion":1,"blocks":[{"id":"","parentID":null,"kind":{"type":"codeBlock","language":""},"content":{"text":"\uD83D\uDE00","marks":[{"kind":{"type":"link","destination":""},"range":{"lowerBound":0,"upperBound":1}}]}}]}"#
        )

        // When
        let blocks = try SlopadEditorArchive.decode(source)

        // Then
        #expect(blocks[0].id.rawValue.isEmpty)
        #expect(blocks[0].kind == .codeBlock(language: ""))
        #expect(blocks[0].content.text == "😀")
        #expect(blocks[0].content.marks[0].kind == .link(destination: ""))
    }

    @Test("알려진 V1 fixture를 decode하고 semantic 재인코딩한다")
    func decodesKnownV1Fixture() throws {
        // Given
        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "known-v1", withExtension: "json", subdirectory: "Fixtures")
        )
        let fixture = try Data(contentsOf: fixtureURL)

        // When
        let blocks = try SlopadEditorArchive.decode(fixture)
        let reencoded = try SlopadEditorArchive.encode(blocks)
        let roundTripped = try SlopadEditorArchive.decode(reencoded)

        // Then
        #expect(blocks.map(\.id) == ["title", "task"])
        #expect(blocks[1].parentID == "title")
        #expect(blocks[1].kind == .todo(isChecked: true))
        #expect(roundTripped == blocks)
    }

    @Test("V1 envelope에는 version과 canonical blocks 외 metadata가 없다")
    func encodedSchemaContainsOnlyTheLockedFields() throws {
        // Given
        let blocks = [EditorBlockInput(id: "root", content: BlockContent(text: "value"))]

        // When
        let data = try SlopadEditorArchive.encode(blocks)
        let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rawBlocks = try #require(envelope["blocks"] as? [[String: Any]])
        let rawBlock = try #require(rawBlocks.first)

        // Then
        #expect(Set(envelope.keys) == ["formatVersion", "blocks"])
        #expect(Set(rawBlock.keys) == ["id", "parentID", "kind", "content"])
        #expect(envelope["selection"] == nil)
        #expect(envelope["revision"] == nil)
        #expect(envelope["composition"] == nil)
        #expect(envelope["storage"] == nil)
    }

    @Test("같은 canonical input의 반복 인코딩은 같은 의미를 만든다")
    func repeatedEncodingIsSemanticallyDeterministic() throws {
        // Given
        let blocks = allKindBlocks(root: "root", child: "child")

        // When
        let first = try SlopadEditorArchive.decode(SlopadEditorArchive.encode(blocks))
        let second = try SlopadEditorArchive.decode(SlopadEditorArchive.encode(blocks))

        // Then
        #expect(first == blocks)
        #expect(second == blocks)
    }

    @Test("future와 past version은 migration 추측 없이 분리된 typed error로 거절한다")
    func unsupportedVersionsFailWithTypedErrors() {
        // Given / When / Then
        #expect(
            throws: SlopadArchiveDecodingError.unsupportedFutureVersion(
                found: 2, latestSupported: 1)
        ) {
            try SlopadEditorArchive.decode(Self.json(#"{"formatVersion":2,"blocks":null}"#))
        }
        #expect(
            throws: SlopadArchiveDecodingError.unsupportedPastVersion(
                found: 0, earliestSupported: 1)
        ) {
            try SlopadEditorArchive.decode(Self.json(#"{"formatVersion":0,"blocks":null}"#))
        }
        #expect(
            throws: SlopadArchiveDecodingError.unsupportedPastVersion(
                found: -1, earliestSupported: 1)
        ) {
            try SlopadEditorArchive.decode(Self.json(#"{"formatVersion":-1,"blocks":null}"#))
        }
    }

    @Test(
        "fractional, exponent, overflow version과 누락 version은 malformed로 거절한다",
        arguments: [
            #"{"formatVersion":1.0,"blocks":[]}"#,
            #"{"formatVersion":1e0,"blocks":[]}"#,
            #"{"formatVersion":999999999999999999999999,"blocks":[]}"#,
            #"{"blocks":[]}"#,
            #"{"formatVersion":"1","blocks":[]}"#,
        ])
    func invalidVersionTokensFailAsMalformed(source: String) {
        // Given / When / Then
        #expect(throws: SlopadArchiveDecodingError.malformedData) {
            try SlopadEditorArchive.decode(Self.json(source))
        }
    }

    @Test("malformed UTF-8, escape, surrogate, duplicate key, unknown field는 모두 거절한다")
    func strictJSONFailuresAreMalformed() {
        // Given
        let invalidUTF8 = Data([0x7B, 0x22, 0x78, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D])
        let malformedSources = [
            #"{"formatVersion":1,"blocks":[],"blocks":[]}"#,
            #"{"formatVersion":1,"blocks":[],"extra":true}"#,
            #"{"formatVersion":1,"blocks":[{"id":"a","id":"b","parentID":null,"kind":{"type":"paragraph"},"content":{"text":"","marks":[]}}]}"#,
            #"{"formatVersion":1,"blocks":[{"id":"\q","parentID":null,"kind":{"type":"paragraph"},"content":{"text":"","marks":[]}}]}"#,
            #"{"formatVersion":1,"blocks":[{"id":"\uD800","parentID":null,"kind":{"type":"paragraph"},"content":{"text":"","marks":[]}}]}"#,
            #"{"formatVersion":1,"blocks":[{"id":"\uDE00","parentID":null,"kind":{"type":"paragraph"},"content":{"text":"","marks":[]}}]}"#,
            #"{"formatVersion":01,"blocks":[]}"#,
            #"{"formatVersion":1,"blocks":[{"id":"a","parentID":null,"kind":{"type":"paragraph"},"content":{"text":""}}]}"#,
            #"{"formatVersion":1,"blocks":[{"id":"a","parentID":null,"kind":{"type":"paragraph"},"content":{"text":"","marks":[],"extra":true}}]}"#,
            #"{"formatVersion":1,"blocks":NaN}"#,
            #"{"formatVersion":1,"blocks":Infinity}"#,
        ]

        // When / Then
        #expect(throws: SlopadArchiveDecodingError.malformedData) {
            try SlopadEditorArchive.decode(invalidUTF8)
        }
        for source in malformedSources {
            #expect(throws: SlopadArchiveDecodingError.malformedData) {
                try SlopadEditorArchive.decode(Self.json(source))
            }
        }
    }

    @Test("archive byte budget은 정확한 경계를 허용하고 한 byte 초과를 거절한다")
    func archiveByteBudgetBoundaryIsExact() throws {
        // Given
        let encoded = try SlopadEditorArchive.encode([
            EditorBlockInput(id: "a", content: BlockContent(text: "a"))
        ])
        let paddingCount = ArchiveWireBudget.v1.maximumArchiveBytes - encoded.count
        var exactBoundary = encoded
        exactBoundary.append(Data(repeating: 0x20, count: paddingCount))
        var overBoundary = exactBoundary
        overBoundary.append(0x20)

        // When
        let decoded = try SlopadEditorArchive.decode(exactBoundary)

        // Then
        #expect(decoded[0].id == "a")
        #expect(throws: SlopadArchiveDecodingError.malformedData) {
            try SlopadEditorArchive.decode(overBoundary)
        }
    }

    @Test("decoded string budget은 UTF-8 byte의 정확한 경계를 사용한다")
    func decodedStringBudgetBoundaryIsExact() throws {
        // Given
        let budget = ArchiveWireBudget.v1
        let exact = Self.json(
            #""\#(String(repeating: "a", count: budget.maximumDecodedStringBytes))""#)
        let over = Self.json(
            #""\#(String(repeating: "a", count: budget.maximumDecodedStringBytes + 1))""#)

        // When
        _ = try StrictJSONParser.parse(exact)

        // Then
        #expect(throws: StrictJSONError.malformed) {
            try StrictJSONParser.parse(over)
        }
    }

    @Test("array element budget은 전체 tree의 정확한 경계를 사용한다")
    func arrayElementBudgetBoundaryIsExact() throws {
        // Given
        let maximum = ArchiveWireBudget.v1.maximumArrayElements
        let exact = Self.repeatedJSONArray(element: "null", count: maximum)
        let over = Self.repeatedJSONArray(element: "null", count: maximum + 1)

        // When
        _ = try StrictJSONParser.parse(exact)

        // Then
        #expect(throws: StrictJSONError.malformed) {
            try StrictJSONParser.parse(over)
        }
    }

    @Test("object member budget은 unknown member도 allocation 전에 제한한다")
    func objectMemberBudgetBoundaryIsExact() throws {
        // Given
        let maximum = ArchiveWireBudget.v1.maximumObjectMembers
        let exact = Self.repeatedJSONObject(memberCount: maximum, arrayValues: 0)
        let over = Self.repeatedJSONObject(memberCount: maximum + 1, arrayValues: 0)

        // When
        _ = try StrictJSONParser.parse(exact)

        // Then
        #expect(throws: StrictJSONError.malformed) {
            try StrictJSONParser.parse(over)
        }
    }

    @Test("value budget은 collection budget과 별도로 정확한 경계를 사용한다")
    func parsedValueBudgetBoundaryIsExact() throws {
        // Given
        let memberCount = ArchiveWireBudget.v1.maximumValues / 2
        let exact = Self.repeatedJSONObject(
            memberCount: memberCount,
            arrayValues: memberCount - 1
        )
        let over = Self.repeatedJSONObject(
            memberCount: memberCount,
            arrayValues: memberCount
        )

        // When
        _ = try StrictJSONParser.parse(exact)

        // Then
        #expect(throws: StrictJSONError.malformed) {
            try StrictJSONParser.parse(over)
        }
    }

    @Test("huge unknown object와 blocks 및 marks array는 partial 없이 malformed로 실패한다")
    func oversizedCollectionsFailWithoutPartialValues() {
        // Given
        let collectionMaximum = ArchiveWireBudget.v1.maximumArrayElements
        let hugeUnknownObject = Self.repeatedJSONObject(
            memberCount: ArchiveWireBudget.v1.maximumObjectMembers + 1,
            arrayValues: 0
        )
        let hugeBlocks = Self.archiveWithRawBlocks(
            String(repeating: "null,", count: collectionMaximum) + "null"
        )
        let hugeMarks = Self.archiveWithMarksPayload(
            String(repeating: "null,", count: collectionMaximum) + "null"
        )

        // When / Then
        for source in [hugeUnknownObject, hugeBlocks, hugeMarks] {
            #expect(throws: SlopadArchiveDecodingError.malformedData) {
                try SlopadEditorArchive.decode(source)
            }
        }
    }

    @Test("encoder는 동일한 decoded-string budget 경계까지만 bytes를 반환한다")
    func encoderUsesTheSameStringBudget() throws {
        // Given
        let fixedDecodedStringBytes = 63
        let exactText = String(
            repeating: "a",
            count: ArchiveWireBudget.v1.maximumDecodedStringBytes - fixedDecodedStringBytes
        )
        let exactBlock = EditorBlockInput(id: "a", content: BlockContent(text: exactText))
        let overBlock = EditorBlockInput(id: "a", content: BlockContent(text: exactText + "a"))

        // When
        let encoded = try SlopadEditorArchive.encode([exactBlock])

        // Then
        #expect(try SlopadEditorArchive.decode(encoded) == [exactBlock])
        #expect(
            throws: SlopadArchiveEncodingError.canonicalInvariant(
                .invalidContent(blockID: "a")
            )
        ) {
            try SlopadEditorArchive.encode([overBlock])
        }
    }

    @Test("encoder는 escaped output의 archive byte budget도 반환 전에 제한한다")
    func encoderUsesTheSameArchiveByteBudget() throws {
        // Given
        let emptyBlock = EditorBlockInput(id: "a", content: BlockContent())
        let fixedArchiveBytes = try SlopadEditorArchive.encode([emptyBlock]).count
        let remainingBytes = ArchiveWireBudget.v1.maximumArchiveBytes - fixedArchiveBytes
        let escapedScalarCount = remainingBytes / 6
        let plainScalarCount = remainingBytes % 6
        let exactText =
            String(repeating: "\0", count: escapedScalarCount)
            + String(repeating: "a", count: plainScalarCount)
        let exactBlock = EditorBlockInput(id: "a", content: BlockContent(text: exactText))
        let overBlock = EditorBlockInput(id: "a", content: BlockContent(text: exactText + "a"))

        // When
        let encoded = try SlopadEditorArchive.encode([exactBlock])

        // Then
        #expect(encoded.count == ArchiveWireBudget.v1.maximumArchiveBytes)
        #expect(try SlopadEditorArchive.decode(encoded) == [exactBlock])
        #expect(
            throws: SlopadArchiveEncodingError.canonicalInvariant(
                .invalidContent(blockID: "a")
            )
        ) {
            try SlopadEditorArchive.encode([overBlock])
        }
    }

    @Test("encoder preflight의 blocks element budget은 exact와 plus one을 구분한다")
    func encoderBlockElementPreflightBoundaryIsExact() throws {
        // Given
        let exactBlocks = (0..<3).map { index in
            EditorBlockInput(id: BlockID("block-\(index)"))
        }
        let overBlocks = exactBlocks + [EditorBlockInput(id: "block-3")]
        let budget = Self.preflightBudget(arrayElements: 3)

        // When
        try ArchiveV1AdmissionPreflight.validate(exactBlocks, budget: budget)

        // Then
        #expect(throws: ArchiveV1EncodingBudgetError.exceeded(blockID: "block-3")) {
            try ArchiveV1AdmissionPreflight.validate(overBlocks, budget: budget)
        }
    }

    @Test("encoder preflight의 marks element budget은 exact와 plus one을 구분한다")
    func encoderMarkElementPreflightBoundaryIsExact() throws {
        // Given
        let exactBlock = Self.blockWithRawMarks(count: 3)
        let overBlock = Self.blockWithRawMarks(count: 4)
        let budget = Self.preflightBudget(arrayElements: 4)

        // When
        try ArchiveV1AdmissionPreflight.validate([exactBlock], budget: budget)

        // Then
        #expect(throws: ArchiveV1EncodingBudgetError.exceeded(blockID: "marked")) {
            try ArchiveV1AdmissionPreflight.validate([overBlock], budget: budget)
        }
    }

    @Test("encoder preflight의 value budget은 exact와 plus one을 구분한다")
    func encoderValuePreflightBoundaryIsExact() throws {
        // Given
        let exactBlock = EditorBlockInput(id: "a", kind: .paragraph)
        let overBlock = EditorBlockInput(id: "a", kind: .heading(level: .h1))
        let budget = Self.preflightBudget(values: 11)

        // When
        try ArchiveV1AdmissionPreflight.validate([exactBlock], budget: budget)

        // Then
        #expect(throws: ArchiveV1EncodingBudgetError.exceeded(blockID: "a")) {
            try ArchiveV1AdmissionPreflight.validate([overBlock], budget: budget)
        }
    }

    @Test("encoder preflight의 object member budget은 exact와 plus one을 구분한다")
    func encoderObjectMemberPreflightBoundaryIsExact() throws {
        // Given
        let exactBlock = EditorBlockInput(id: "a", kind: .paragraph)
        let overBlock = EditorBlockInput(id: "a", kind: .heading(level: .h1))
        let budget = Self.preflightBudget(objectMembers: 9)

        // When
        try ArchiveV1AdmissionPreflight.validate([exactBlock], budget: budget)

        // Then
        #expect(throws: ArchiveV1EncodingBudgetError.exceeded(blockID: "a")) {
            try ArchiveV1AdmissionPreflight.validate([overBlock], budget: budget)
        }
    }

    @Test("encoder preflight byte count는 모든 kind와 mark의 writer output과 일치한다")
    func encoderPreflightByteCountMatchesWriter() throws {
        // Given
        let blocks = allKindBlocks(root: "root", child: "child")
        let encoded = try ArchiveV1Encoder.encode(blocks)
        let exactBudget = Self.preflightBudget(archiveBytes: encoded.count)
        let underBudget = Self.preflightBudget(archiveBytes: encoded.count - 1)

        // When
        try ArchiveV1AdmissionPreflight.validate(blocks, budget: exactBudget)

        // Then
        #expect(throws: ArchiveV1EncodingBudgetError.self) {
            try ArchiveV1AdmissionPreflight.validate(blocks, budget: underBudget)
        }
    }

    @Test("over-cap encoder input은 canonical validator 진입 전에 거절한다")
    func encoderBudgetAdmissionPrecedesCanonicalValidation() {
        // Given
        let blockCount = ArchiveWireBudget.v1.maximumObjectMembers / 7 + 2
        let blocks = (0..<blockCount).map { index in
            EditorBlockInput(id: BlockID("preflight-\(index)"))
        }
        var canonicalValidationEntryCount = 0

        // When
        do {
            _ = try SlopadEditorArchive.encodeForTesting(blocks) {
                canonicalValidationEntryCount += 1
            }
            Issue.record("over-cap input unexpectedly encoded")
        } catch {
            // Then
            guard case .canonicalInvariant(.invalidContent) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
            #expect(canonicalValidationEntryCount == 0)
        }
    }

    @Test("over-cap marks도 canonical content 검사 전에 거절한다")
    func encoderMarkBudgetAdmissionPrecedesCanonicalValidation() {
        // Given
        let markCount = (ArchiveWireBudget.v1.maximumObjectMembers - 9) / 5 + 1
        let block = Self.blockWithRawMarks(count: markCount)
        var canonicalValidationEntryCount = 0

        // When
        do {
            _ = try SlopadEditorArchive.encodeForTesting([block]) {
                canonicalValidationEntryCount += 1
            }
            Issue.record("over-cap marks unexpectedly encoded")
        } catch {
            // Then
            guard case .canonicalInvariant(.invalidContent(blockID: "marked")) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
            #expect(canonicalValidationEntryCount == 0)
        }
    }

    @Test(
        "unknown enum과 잘못된 associated payload는 malformed로 거절한다",
        arguments: [
            #"{"type":"table"}"#,
            #"{"type":"heading"}"#,
            #"{"type":"heading","level":4}"#,
            #"{"type":"paragraph","level":1}"#,
            #"{"type":"todo","isChecked":1}"#,
            #"{"type":"orderedListItem"}"#,
            #"{"type":"codeBlock"}"#,
        ])
    func invalidKindPayloadFailsAsMalformed(kind: String) {
        // Given
        let source = Self.blockArchive(kind: kind)

        // When / Then
        #expect(throws: SlopadArchiveDecodingError.malformedData) {
            try SlopadEditorArchive.decode(Self.json(source))
        }
    }

    @Test(
        "unknown mark enum과 잘못된 mark payload는 malformed로 거절한다",
        arguments: [
            #"{"type":"unknown"}"#,
            #"{"type":"link"}"#,
            #"{"type":"strong","destination":"extra"}"#,
        ])
    func invalidMarkKindPayloadFailsAsMalformed(markKind: String) {
        // Given
        let source = Self.archiveWithMarks(
            text: "a",
            marks: [Self.markJSON(type: markKind, lower: 0, upper: 1)]
        )

        // When / Then
        #expect(throws: SlopadArchiveDecodingError.malformedData) {
            try SlopadEditorArchive.decode(Self.json(source))
        }
    }

    @Test(
        "mark range의 fractional, exponent, overflow integer token은 malformed로 거절한다",
        arguments: [
            "0.0", "1e0", "999999999999999999999999",
        ])
    func invalidMarkIntegerTokensFailAsMalformed(token: String) {
        // Given
        let source =
            #"{"formatVersion":1,"blocks":[{"id":"a","parentID":null,"kind":{"type":"paragraph"},"content":{"text":"a","marks":[{"kind":{"type":"strong"},"range":{"lowerBound":0,"upperBound":\#(token)}}]}}]}"#

        // When / Then
        #expect(throws: SlopadArchiveDecodingError.malformedData) {
            try SlopadEditorArchive.decode(Self.json(source))
        }
    }

    @Test(
        "mark primitive range bounds는 Core TextRange 생성 전에 거절한다",
        arguments: [
            (-1, 1), (0, 0), (2, 1), (0, 4),
        ])
    func invalidPrimitiveMarkBoundsFailAsMalformed(lower: Int, upper: Int) {
        // Given
        let source = Self.archiveWithMarks(
            text: "abc",
            marks: [Self.markJSON(type: #"{"type":"strong"}"#, lower: lower, upper: upper)]
        )

        // When / Then
        #expect(throws: SlopadArchiveDecodingError.malformedData) {
            try SlopadEditorArchive.decode(Self.json(source))
        }
    }

    @Test(
        "정규화가 필요한 mark는 성공 값으로 세탁하지 않고 invalidContent로 거절한다",
        arguments: [
            [
                markJSON(type: #"{"type":"strong"}"#, lower: 0, upper: 2),
                markJSON(type: #"{"type":"strong"}"#, lower: 2, upper: 4),
            ],
            [
                markJSON(type: #"{"type":"strong"}"#, lower: 0, upper: 3),
                markJSON(type: #"{"type":"strong"}"#, lower: 1, upper: 2),
            ],
            [
                markJSON(type: #"{"type":"strong"}"#, lower: 2, upper: 4),
                markJSON(type: #"{"type":"emphasis"}"#, lower: 0, upper: 1),
            ],
        ])
    func noncanonicalMarksFailAsInvalidContent(marks: [String]) {
        // Given
        let source = Self.archiveWithMarks(text: "abcd", marks: marks)

        // When / Then
        #expect(
            throws: SlopadArchiveDecodingError.canonicalInvariant(.invalidContent(blockID: "a"))
        ) {
            try SlopadEditorArchive.decode(Self.json(source))
        }
    }

    @Test("서로 다른 mark kind의 overlap은 canonical content로 보존한다")
    func differentMarkKindsMayOverlap() throws {
        // Given
        let source = Self.archiveWithMarks(
            text: "abcd",
            marks: [
                Self.markJSON(type: #"{"type":"strong"}"#, lower: 0, upper: 3),
                Self.markJSON(type: #"{"type":"emphasis"}"#, lower: 1, upper: 2),
            ]
        )

        // When
        let blocks = try SlopadEditorArchive.decode(Self.json(source))

        // Then
        #expect(blocks[0].content.marks.count == 2)
    }

    @Test(
        "document invariant 실패는 partial blocks 없이 typed error를 반환한다",
        arguments: [
            (#"{"formatVersion":1,"blocks":[]}"#, SlopadArchiveCanonicalInvariant.emptyDocument),
            (twoBlockArchive(secondID: "a", secondParent: nil), .duplicateBlockID("a")),
            (
                twoBlockArchive(secondID: "b", secondParent: "missing"),
                .missingParent(blockID: "b", parentID: "missing")
            ),
            (cycleArchive(), .cycleDetected("a")),
            (noncanonicalOrderArchive(), .noncanonicalDepthFirstOrder),
        ])
    func invalidDocumentFailsClosed(source: String, invariant: SlopadArchiveCanonicalInvariant) {
        // Given / When / Then
        #expect(throws: SlopadArchiveDecodingError.canonicalInvariant(invariant)) {
            try SlopadEditorArchive.decode(Self.json(source))
        }
    }

    @Test("encode도 shared canonical validator를 사용하고 bytes를 반환하지 않는다")
    func encodeRejectsInvalidCanonicalInput() {
        // Given
        var invalidContent = BlockContent(text: "abcd")
        invalidContent.marks = [
            .init(kind: .strong, range: TextRange(2, 4)),
            .init(kind: .emphasis, range: TextRange(0, 1)),
        ]
        let invalidContentBlocks = [EditorBlockInput(id: "a", content: invalidContent)]
        let invalidOrderBlocks = [
            EditorBlockInput(id: "a"),
            EditorBlockInput(id: "b"),
            EditorBlockInput(id: "child", parentID: "a"),
        ]

        // When / Then
        #expect(
            throws: SlopadArchiveEncodingError.canonicalInvariant(.invalidContent(blockID: "a"))
        ) {
            try SlopadEditorArchive.encode(invalidContentBlocks)
        }
        #expect(throws: SlopadArchiveEncodingError.canonicalInvariant(.noncanonicalDepthFirstOrder))
        {
            try SlopadEditorArchive.encode(invalidOrderBlocks)
        }
    }

    private func allKindBlocks(root: BlockID, child: BlockID) -> [EditorBlockInput] {
        let markedContent = BlockContent(
            text: "abcdef",
            marks: [
                .init(kind: .strong, range: TextRange(0, 3)),
                .init(kind: .emphasis, range: TextRange(1, 2)),
                .init(kind: .code, range: TextRange(3, 4)),
                .init(kind: .strikethrough, range: TextRange(4, 5)),
                .init(
                    kind: .link(destination: "https://example.com?q=\"x\""), range: TextRange(5, 6)),
            ]
        )
        return [
            EditorBlockInput(id: root, kind: .paragraph, content: markedContent),
            EditorBlockInput(
                id: child, parentID: root, kind: .heading(level: .h1),
                content: BlockContent(text: "child")),
            EditorBlockInput(id: "h2", kind: .heading(level: .h2)),
            EditorBlockInput(id: "h3", kind: .heading(level: .h3)),
            EditorBlockInput(id: "ul", kind: .unorderedListItem),
            EditorBlockInput(id: "ol-nil", kind: .orderedListItem(restartNumber: nil)),
            EditorBlockInput(id: "ol-value", kind: .orderedListItem(restartNumber: -3)),
            EditorBlockInput(id: "quote", kind: .quote),
            EditorBlockInput(id: "code-nil", kind: .codeBlock(language: nil)),
            EditorBlockInput(id: "code-value", kind: .codeBlock(language: "swift")),
            EditorBlockInput(id: "divider", kind: .divider),
            EditorBlockInput(id: "todo", kind: .todo(isChecked: true)),
        ]
    }

    private static func json(_ source: String) -> Data { Data(source.utf8) }

    private static func repeatedJSONArray(element: String, count: Int) -> Data {
        guard count > 0 else { return json("[]") }
        return json("[" + String(repeating: element + ",", count: count - 1) + element + "]")
    }

    private static func preflightBudget(
        archiveBytes: Int = .max,
        values: Int = .max,
        arrayElements: Int = .max,
        objectMembers: Int = .max
    ) -> ArchiveWireBudget {
        ArchiveWireBudget(
            maximumArchiveBytes: archiveBytes,
            maximumValues: values,
            maximumArrayElements: arrayElements,
            maximumObjectMembers: objectMembers,
            maximumDecodedStringBytes: .max
        )
    }

    private static func blockWithRawMarks(count: Int) -> EditorBlockInput {
        var content = BlockContent(text: "a")
        content.marks = Array(
            repeating: .init(kind: .strong, range: TextRange(0, 1)),
            count: count
        )
        return EditorBlockInput(id: "marked", content: content)
    }

    private static func repeatedJSONObject(memberCount: Int, arrayValues: Int) -> Data {
        precondition(arrayValues <= memberCount)
        var source = "{"
        source.reserveCapacity(memberCount * 14)
        for index in 0..<memberCount {
            if index > 0 { source.append(",") }
            source.append(#""k\#(index)":"#)
            source.append(index < arrayValues ? "[null]" : "null")
        }
        source.append("}")
        return json(source)
    }

    private static func archiveWithRawBlocks(_ blocks: String) -> Data {
        json(#"{"formatVersion":1,"blocks":[\#(blocks)]}"#)
    }

    private static func archiveWithMarksPayload(_ marks: String) -> Data {
        json(
            #"{"formatVersion":1,"blocks":[{"id":"a","parentID":null,"kind":{"type":"paragraph"},"content":{"text":"a","marks":[\#(marks)]}}]}"#
        )
    }

    private static func blockArchive(kind: String) -> String {
        #"{"formatVersion":1,"blocks":[{"id":"a","parentID":null,"kind":\#(kind),"content":{"text":"","marks":[]}}]}"#
    }

    private static func archiveWithMarks(text: String, marks: [String]) -> String {
        #"{"formatVersion":1,"blocks":[{"id":"a","parentID":null,"kind":{"type":"paragraph"},"content":{"text":"\#(text)","marks":[\#(marks.joined(separator: ","))]}}]}"#
    }

    private static func markJSON(type: String, lower: Int, upper: Int) -> String {
        #"{"kind":\#(type),"range":{"lowerBound":\#(lower),"upperBound":\#(upper)}}"#
    }

    private static func twoBlockArchive(secondID: String, secondParent: String?) -> String {
        let parent = secondParent.map { #""\#($0)""# } ?? "null"
        return
            #"{"formatVersion":1,"blocks":[{"id":"a","parentID":null,"kind":{"type":"paragraph"},"content":{"text":"","marks":[]}},{"id":"\#(secondID)","parentID":\#(parent),"kind":{"type":"paragraph"},"content":{"text":"","marks":[]}}]}"#
    }

    private static func cycleArchive() -> String {
        #"{"formatVersion":1,"blocks":[{"id":"a","parentID":"b","kind":{"type":"paragraph"},"content":{"text":"","marks":[]}},{"id":"b","parentID":"a","kind":{"type":"paragraph"},"content":{"text":"","marks":[]}}]}"#
    }

    private static func noncanonicalOrderArchive() -> String {
        #"{"formatVersion":1,"blocks":[{"id":"a","parentID":null,"kind":{"type":"paragraph"},"content":{"text":"","marks":[]}},{"id":"b","parentID":null,"kind":{"type":"paragraph"},"content":{"text":"","marks":[]}},{"id":"child","parentID":"a","kind":{"type":"paragraph"},"content":{"text":"","marks":[]}}]}"#
    }
}
