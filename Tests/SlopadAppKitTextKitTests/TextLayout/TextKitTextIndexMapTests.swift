import Foundation
import Testing

@testable import SlopadAppKitTextKit
@testable import SlopadCoreModel

@Suite("TextKit 텍스트 인덱스 맵")
struct TextKitTextIndexMapTests {
    @Test("ASCII와 CRLF, 결합 문자, ZWJ 이모지의 grapheme 경계를 UTF-16과 왕복한다")
    func complexGraphemeBoundariesRoundTrip() {
        // Given
        let text = "A\r\ne\u{301}👨‍👩‍👧‍👦B"
        let map = TextKitTextIndexMap(text: text)
        let expectedUTF16Boundaries = [0, 1, 3, 5, 16, 17]

        // When
        let utf16Boundaries = (0...map.graphemeCount).compactMap {
            map.utf16Offset(forGraphemeOffset: $0)
        }
        let roundTripped = expectedUTF16Boundaries.map {
            map.textRange(for: NSRange(location: $0, length: 0))
        }
        let combinedRange = map.nsRange(clamping: TextRange(1, 4))

        // Then
        #expect(map.graphemeCount == 5)
        #expect(map.utf16Count == 17)
        #expect(utf16Boundaries == expectedUTF16Boundaries)
        #expect(roundTripped == (0...5).map { TextRange.point($0) })
        #expect(combinedRange == NSRange(location: 1, length: 15))
    }

    @Test("grapheme 내부와 잘못된 UTF-16 범위는 인접 경계로 보정하지 않는다")
    func invalidUTF16BoundariesAreRejected() {
        // Given
        let map = TextKitTextIndexMap(text: "A\r\ne\u{301}👨‍👩‍👧‍👦B")
        let invalidRanges = [
            NSRange(location: 2, length: 0),
            NSRange(location: 4, length: 0),
            NSRange(location: 6, length: 0),
            NSRange(location: 1, length: 1),
            NSRange(location: -1, length: 0),
            NSRange(location: 18, length: 0),
            NSRange(location: NSNotFound, length: 1),
        ]

        // When
        let converted = invalidRanges.map(map.textRange(for:))

        // Then
        #expect(converted.allSatisfy { $0 == nil })
        #expect(map.utf16Offset(forGraphemeOffset: -1) == nil)
        #expect(map.utf16Offset(forGraphemeOffset: 6) == nil)
    }

    @Test("내부 sentinel 범위는 canonical UTF-16 끝으로만 숫자 clamp한다")
    func sentinelRangeClampsToCanonicalEnd() {
        // Given
        let map = TextKitTextIndexMap(text: "A\n")
        let sentinelRange = NSRange(location: 2, length: 1)
        let pastEndRange = NSRange(location: 3, length: 0)
        let overflowingRange = NSRange(location: Int.max - 1, length: 4)

        // When
        let clampedSentinel = map.clampedUTF16Range(sentinelRange)
        let clampedPastEnd = map.clampedUTF16Range(pastEndRange)

        // Then
        #expect(clampedSentinel == NSRange(location: 2, length: 0))
        #expect(clampedPastEnd == NSRange(location: 2, length: 0))
        #expect(clampedSentinel.flatMap(map.textRange(for:)) == .point(2))
        #expect(map.extendsPastUTF16Bounds(sentinelRange))
        #expect(map.extendsPastUTF16Bounds(pastEndRange))
        #expect(map.clampedUTF16Range(overflowingRange) == nil)
        #expect(!map.extendsPastUTF16Bounds(overflowingRange))
    }
}
