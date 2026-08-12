import Testing

@testable import SlopadEditorDataStructure

@Suite("prefix sum red-black tree 노드 핸들")
struct PrefixSumRedBlackTreeHandleTests {
    @Test("삭제된 노드 핸들은 조회에서 거부된다")
    func removedNodeHandleIsRejectedByLookups() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
        ]
        let removedNodeIndex = 1
        let expectedRemovedValue: String? = "b"
        let expectedRank: Int? = nil
        let expectedPrefixSum: Double? = nil
        let nodes = insertEntries(entries, into: tree)

        // When
        let removedValue = tree.remove(node: nodes[removedNodeIndex])
        let rank = tree.rank(of: nodes[removedNodeIndex])
        let prefixSum = tree.prefixSum(upTo: nodes[removedNodeIndex])

        // Then
        #expect(removedValue == expectedRemovedValue)
        #expect(rank == expectedRank)
        #expect(prefixSum == expectedPrefixSum)
    }

    @Test("삭제된 노드 핸들은 변경 요청에서 거부된다")
    func removedNodeHandleIsRejectedByMutations() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
        ]
        let removedNodeIndex = 1
        let staleUpdate = (value: "stale", aggregate: 1.0)
        let expectedUpdateResult = false
        let expectedSecondRemoval: String? = nil
        let expectedValues = ["a", "c"]
        let nodes = insertEntries(entries, into: tree)
        tree.remove(node: nodes[removedNodeIndex])

        // When
        let didUpdate = tree.update(
            nodes[removedNodeIndex],
            value: staleUpdate.value,
            aggregate: staleUpdate.aggregate
        )
        let secondRemoval = tree.remove(node: nodes[removedNodeIndex])
        let values = tree.valuesInOrder()

        // Then
        #expect(didUpdate == expectedUpdateResult)
        #expect(secondRemoval == expectedSecondRemoval)
        #expect(values == expectedValues)
    }

    @Test("다른 트리의 노드 핸들은 조회에서 거부된다")
    func foreignNodeHandleIsRejectedByLookups() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let other = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
        ]
        let foreignEntry = (value: "foreign", aggregate: 99.0)
        let expectedRank: Int? = nil
        let expectedPrefixSum: Double? = nil
        insertEntries(entries, into: tree)
        let foreignNode = other.insert(
            value: foreignEntry.value,
            aggregate: foreignEntry.aggregate,
            at: 0
        )

        // When
        let rank = tree.rank(of: foreignNode)
        let prefixSum = tree.prefixSum(upTo: foreignNode)

        // Then
        #expect(rank == expectedRank)
        #expect(prefixSum == expectedPrefixSum)
    }

    @Test("다른 트리의 노드 핸들은 변경 요청에서 거부된다")
    func foreignNodeHandleIsRejectedByMutations() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let other = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
        ]
        let foreignEntry = (value: "foreign", aggregate: 99.0)
        let staleUpdate = (value: "stale", aggregate: 1.0)
        let expectedRemovedValue: String? = nil
        let expectedUpdateResult = false
        let expectedValues = ["a", "b", "c"]
        let expectedOtherValues = [foreignEntry.value]
        insertEntries(entries, into: tree)
        let foreignNode = other.insert(
            value: foreignEntry.value,
            aggregate: foreignEntry.aggregate,
            at: 0
        )

        // When
        let removedValue = tree.remove(node: foreignNode)
        let didUpdate = tree.update(
            foreignNode,
            value: staleUpdate.value,
            aggregate: staleUpdate.aggregate
        )
        let values = tree.valuesInOrder()
        let otherValues = other.valuesInOrder()

        // Then
        #expect(removedValue == expectedRemovedValue)
        #expect(didUpdate == expectedUpdateResult)
        #expect(values == expectedValues)
        #expect(otherValues == expectedOtherValues)
    }

    @Test("전체 삭제가 기존 노드 핸들의 조회를 무효화한다")
    func removeAllInvalidatesOldNodeHandleLookups() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
        ]
        let expectedRanks: [Int?] = [nil, nil, nil]
        let expectedPrefixSums: [Double?] = [nil, nil, nil]
        let nodes = insertEntries(entries, into: tree)

        // When
        tree.removeAll()
        let ranks = nodes.map { tree.rank(of: $0) }
        let prefixSums = nodes.map { tree.prefixSum(upTo: $0) }

        // Then
        #expect(ranks == expectedRanks)
        #expect(prefixSums == expectedPrefixSums)
    }

    @Test("전체 삭제가 기존 노드 핸들의 변경 요청을 거부한다")
    func removeAllRejectsOldNodeHandleMutations() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
        ]
        let staleUpdate = (value: "stale", aggregate: 1.0)
        let expectedRemovedValues: [String?] = [nil, nil, nil]
        let expectedUpdateResults = [false, false, false]
        let nodes = insertEntries(entries, into: tree)

        // When
        tree.removeAll()
        let removedValues = nodes.map { tree.remove(node: $0) }
        let updateResults = nodes.map {
            tree.update($0, value: staleUpdate.value, aggregate: staleUpdate.aggregate)
        }

        // Then
        #expect(removedValues == expectedRemovedValues)
        #expect(updateResults == expectedUpdateResults)
    }

    @Test("저장한 노드 핸들은 회전 이후에도 갱신할 수 있다")
    func storedNodeHandleCanBeUpdatedAfterRotations() {
        // Given
        let tree = PrefixSumRedBlackTree<Int>()
        let first = (value: 1, aggregate: 10.0)
        let second = (value: 2, aggregate: 20.0)
        let third = (value: 3, aggregate: 30.0)
        let head = (value: 0, aggregate: 5.0)
        let middle = (value: 15, aggregate: 15.0)
        let updatedSecond = (value: 20, aggregate: 25.0)
        let expectedUpdateResult = true
        let expectedRank: Int? = 3
        let expectedPrefixSum: Double? = head.aggregate + first.aggregate + middle.aggregate
        let expectedValues = [
            head.value, first.value, middle.value, updatedSecond.value, third.value,
        ]
        tree.insert(value: first.value, aggregate: first.aggregate, at: 0)
        let secondNode = tree.insert(value: second.value, aggregate: second.aggregate, at: 1)
        tree.insert(value: third.value, aggregate: third.aggregate, at: 2)
        tree.insert(value: head.value, aggregate: head.aggregate, at: 0)
        tree.insert(value: middle.value, aggregate: middle.aggregate, at: 2)

        // When
        let didUpdate = tree.update(
            secondNode,
            value: updatedSecond.value,
            aggregate: updatedSecond.aggregate
        )
        let rank = tree.rank(of: secondNode)
        let prefixSum = tree.prefixSum(upTo: secondNode)
        let values = tree.valuesInOrder()

        // Then
        #expect(didUpdate == expectedUpdateResult)
        #expect(rank == expectedRank)
        #expect(prefixSum == expectedPrefixSum)
        #expect(values == expectedValues)
    }
}
