import Testing

@testable import SlopadEditorDataStructure

@Suite("prefix sum red-black tree prefix 조회")
struct PrefixSumRedBlackTreePrefixQueryTests {
    @Test("index 기준 prefix sum이 기대 누적합을 반환한다")
    func prefixSumUpToIndexReturnsExpectedAccumulation() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let a = (value: "a", aggregate: 10.0)
        let b = (value: "b", aggregate: 20.0)
        let c = (value: "c", aggregate: 30.0)
        let d = (value: "d", aggregate: 40.0)
        let entries: [(value: String, aggregate: Double)] = [a, b, c, d]
        let queriedIndices = [-10, 0, 1, 2, 3, 4, 99]
        let expectedPrefixSums = [
            0.0,
            0.0,
            a.aggregate,
            a.aggregate + b.aggregate,
            a.aggregate + b.aggregate + c.aggregate,
            a.aggregate + b.aggregate + c.aggregate + d.aggregate,
            a.aggregate + b.aggregate + c.aggregate + d.aggregate,
        ]
        let expectedTotalAggregate =
            a.aggregate + b.aggregate + c.aggregate + d.aggregate
        insertEntries(entries, into: tree)

        // When
        let prefixSums = queriedIndices.map { tree.prefixSum(upTo: $0) }
        let totalAggregate = tree.totalAggregate

        // Then
        #expect(prefixSums == expectedPrefixSums)
        #expect(totalAggregate == expectedTotalAggregate)
    }

    @Test("노드 기준 prefix sum이 노드 이전 누적합을 반환한다")
    func prefixSumUpToNodeReturnsAccumulationBeforeNode() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let a = (value: "a", aggregate: 10.0)
        let b = (value: "b", aggregate: 20.0)
        let c = (value: "c", aggregate: 30.0)
        let entries: [(value: String, aggregate: Double)] = [a, b, c]
        let queriedNodeIndex = 2
        let expectedPrefixSum: Double? = a.aggregate + b.aggregate
        let nodes = insertEntries(entries, into: tree)

        // When
        let prefixSum = tree.prefixSum(upTo: nodes[queriedNodeIndex])

        // Then
        #expect(prefixSum == expectedPrefixSum)
    }

    @Test("Y 위치 조회가 해당 aggregate 구간의 노드를 반환한다")
    func prefixPositionLookupReturnsContainingNode() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
            (value: "d", aggregate: 40),
            // [0, 10, 30, 60, 100]
        ]
        let positions = [-1, 0, 9.999, 10, 29.999, 30, 59.999, 60, 99.999, 100]
        let expectedValues: [String?] = [
            "a",
            "a",
            "a",
            "b",
            "b",
            "c",
            "c",
            "d",
            "d",
            nil,
        ]
        insertEntries(entries, into: tree)

        // When
        let values = positions.map { tree.node(containingPrefixPosition: $0)?.value }

        // Then
        #expect(values == expectedValues)
    }

    @Test("Y 위치 조회가 해당 aggregate 구간의 index를 반환한다")
    func prefixPositionLookupReturnsContainingIndex() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
            (value: "d", aggregate: 40),
            // [0, 10, 30, 60, 100]
        ]
        let positions = [-1, 0, 9.999, 10, 29.999, 30, 59.999, 60, 99.999, 100]
        let expectedIndices: [Int?] = [0, 0, 0, 1, 1, 2, 2, 3, 3, nil]
        insertEntries(entries, into: tree)

        // When
        let indices = positions.map { tree.index(containingPrefixPosition: $0) }

        // Then
        #expect(indices == expectedIndices)
    }

    @Test("prefix lower-bound 조회가 목표 누적합 이상의 첫 index를 반환한다")
    func firstIndexWithPrefixSumReturnsLowerBoundIndex() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
            (value: "d", aggregate: 40),
            // [0, 10, 30, 60, 100]
        ]
        let targets = [-1, 0, 0.001, 10, 10.001, 30, 30.001, 60, 60.001, 100, 101]
        let expectedIndices = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 4]
        insertEntries(entries, into: tree)

        // When
        let indices = targets.map { tree.firstIndexWithPrefixSum(atLeast: $0) }

        // Then
        #expect(indices == expectedIndices)
    }

    @Test("0 aggregate는 prefix sum 경계를 유지한다")
    func zeroAggregateKeepsPrefixSumBoundaries() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let zeroHead = (value: "zero-head", aggregate: 0.0)
        let ten = (value: "ten", aggregate: 10.0)
        let zeroMiddle = (value: "zero-middle", aggregate: 0.0)
        let five = (value: "five", aggregate: 5.0)
        let entries: [(value: String, aggregate: Double)] = [
            zeroHead,
            ten,
            zeroMiddle,
            five,
        ]
        let queriedIndices = [0, 1, 2, 3, 4]
        let expectedPrefixSums = [
            0.0,
            zeroHead.aggregate,
            zeroHead.aggregate + ten.aggregate,
            zeroHead.aggregate + ten.aggregate + zeroMiddle.aggregate,
            zeroHead.aggregate + ten.aggregate + zeroMiddle.aggregate + five.aggregate,
        ]
        insertEntries(entries, into: tree)

        // When
        let prefixSums = queriedIndices.map { tree.prefixSum(upTo: $0) }

        // Then
        #expect(prefixSums == expectedPrefixSums)
    }

    @Test("0 aggregate는 lower-bound 경계를 유지한다")
    func zeroAggregateKeepsLowerBoundBoundaries() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let zeroHead = (value: "zero-head", aggregate: 0.0)
        let ten = (value: "ten", aggregate: 10.0)
        let zeroMiddle = (value: "zero-middle", aggregate: 0.0)
        let five = (value: "five", aggregate: 5.0)
        let entries: [(value: String, aggregate: Double)] = [
            zeroHead,
            ten,
            zeroMiddle,
            five,
        ]
        let targets = [0.0, 0.001, 10, 10.001]
        let expectedLowerBoundIndices = [0, 2, 2, 4]
        insertEntries(entries, into: tree)

        // When
        let lowerBoundIndices = targets.map { tree.firstIndexWithPrefixSum(atLeast: $0) }

        // Then
        #expect(lowerBoundIndices == expectedLowerBoundIndices)
    }

    @Test("0 aggregate 노드는 Y 위치를 점유하지 않는다")
    func zeroAggregateNodeDoesNotContainPosition() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "zero-head", aggregate: 0),
            (value: "ten", aggregate: 10),
            (value: "zero-middle", aggregate: 0),
            (value: "five", aggregate: 5),
        ]
        let positions = [0.0, 9.999, 10, 15]
        let expectedValues: [String?] = ["ten", "ten", "five", nil]
        let expectedIndices: [Int?] = [1, 1, 3, nil]
        insertEntries(entries, into: tree)

        // When
        let values = positions.map { tree.node(containingPrefixPosition: $0)?.value }
        let indices = positions.map { tree.index(containingPrefixPosition: $0) }

        // Then
        #expect(values == expectedValues)
        #expect(indices == expectedIndices)
    }
}
