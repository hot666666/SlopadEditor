import Testing

@testable import SlopadEditorDataStructure

@Suite("prefix sum red-black tree 불변식")
struct PrefixSumRedBlackTreeInvariantTests {
    @Test("단조 삽입도 red-black 높이 상한을 유지한다")
    func monotonicInsertionsStayWithinRedBlackHeightBound() {
        // Given
        let tree = PrefixSumRedBlackTree<Int>()
        let insertedValues = Array(0..<512)
        let expectedValues = insertedValues

        // When
        for value in insertedValues {
            tree.insert(value: value, aggregate: Double(value + 1), at: tree.count)
        }
        let values = tree.valuesInOrder()

        // Then
        #expect(values == expectedValues)
        assertRedBlackInvariantsHold(tree, context: "after monotonic insertions")
        assertTreeHeightStaysWithinRedBlackBound(tree, context: "after monotonic insertions")
    }

    @Test("일괄 구성은 순서와 prefix 조회를 유지한다")
    func replaceAllBuildsOrderedPrefixTree() {
        // Given
        let tree = PrefixSumRedBlackTree<Int>()
        let insertedValues = Array(0..<513)
        let entries = insertedValues.map { value in
            (value: value, aggregate: Double(value + 1))
        }
        let queriedIndexes = [0, 1, 256, 513]
        let expectedPrefixSums = [
            0.0,
            1.0,
            Double((1...256).reduce(0, +)),
            Double((1...513).reduce(0, +)),
        ]
        let rankedIndexes = [0, 256, 512]
        let expectedRanks = rankedIndexes

        // When
        let nodes = tree.replaceAll(with: entries)
        let values = tree.valuesInOrder()
        let prefixSums = queriedIndexes.map { tree.prefixSum(upTo: $0) }
        let ranks = rankedIndexes.map { tree.rank(of: nodes[$0]) }

        // Then
        #expect(values == insertedValues)
        #expect(prefixSums == expectedPrefixSums)
        #expect(ranks == expectedRanks)
        assertRedBlackInvariantsHold(tree, context: "after bulk replace")
        assertTreeHeightStaysWithinRedBlackBound(tree, context: "after bulk replace")
    }

    @Test("단조 삽입 후 삭제도 red-black 높이 상한을 유지한다")
    func deletionsAfterMonotonicInsertionsStayWithinRedBlackHeightBound() {
        // Given
        enum DeletionPosition {
            case first, middle, last

            func index(in count: Int) -> Int {
                switch self {
                case .first: return 0
                case .middle: return count / 2
                case .last: return count - 1
                }
            }
        }
        let tree = PrefixSumRedBlackTree<Int>()
        let insertedValues = Array(0..<512)
        let deletionPattern: [DeletionPosition] = [.first, .middle, .last]
        let expectedValuesAfterDeletion: [Int] = []
        for value in insertedValues {
            tree.insert(value: value, aggregate: Double(value + 1), at: tree.count)
        }

        // When
        for deletionStep in insertedValues.indices {
            let deletionPosition = deletionPattern[deletionStep % deletionPattern.count]
            let deletionIndex = deletionPosition.index(in: tree.count)

            tree.remove(at: deletionIndex)

            assertRedBlackInvariantsHold(
                tree,
                context: "after deleting \(deletionPosition) at step \(deletionStep)"
            )
            assertTreeHeightStaysWithinRedBlackBound(
                tree,
                context: "after deleting \(deletionPosition) at step \(deletionStep)"
            )
        }
        let values = tree.valuesInOrder()

        // Then
        #expect(values == expectedValuesAfterDeletion)
    }
}
