import Testing

@testable import SlopadEditorDataStructure

@Suite("prefix sum red-black tree 변경")
struct PrefixSumRedBlackTreeMutationTests {
    @Test("지정 index 삽입이 기대 순서를 만든다")
    func insertAtRequestedIndicesKeepsExpectedOrder() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let insertions: [(value: String, aggregate: Double, index: Int)] = [
            (value: "a", aggregate: 10, index: 0),
            (value: "b", aggregate: 20, index: 1),
            (value: "c", aggregate: 30, index: 2),
            (value: "head", aggregate: 5, index: 0),
            (value: "middle", aggregate: 15, index: 2),
            (value: "tail", aggregate: 8, index: 5),
        ]
        let expectedValues = ["head", "a", "middle", "b", "c", "tail"]
        let expectedCount = expectedValues.count

        // When
        for insertion in insertions {
            tree.insert(value: insertion.value, aggregate: insertion.aggregate, at: insertion.index)
        }

        // Then
        let values = tree.valuesInOrder()
        let count = tree.count
        #expect(values == expectedValues)
        #expect(count == expectedCount)
    }

    @Test("범위를 벗어난 삽입 index는 앞과 뒤로 보정된다")
    func insertClampsOutOfRangeIndices() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let insertions: [(value: String, aggregate: Double, index: Int)] = [
            (value: "b", aggregate: 20, index: 0),
            (value: "a", aggregate: 10, index: -100),
            (value: "c", aggregate: 30, index: 100),
        ]
        let expectedValues = ["a", "b", "c"]

        // When
        for insertion in insertions {
            tree.insert(value: insertion.value, aggregate: insertion.aggregate, at: insertion.index)
        }

        // Then
        let values = tree.valuesInOrder()
        #expect(values == expectedValues)
    }

    @Test("노드 갱신이 저장 값을 바꾼다")
    func updateChangesStoredValue() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let a = (value: "a", aggregate: 10.0)
        let b = (value: "b", aggregate: 20.0)
        let c = (value: "c", aggregate: 30.0)
        let updatedB = (value: "updated-b", aggregate: 50.0)
        let entries: [(value: String, aggregate: Double)] = [a, b, c]
        let updatedNodeIndex = 1
        let expectedUpdateResult = true
        let expectedValues = [a.value, updatedB.value, c.value]
        let nodes = insertEntries(entries, into: tree)

        // When
        let didUpdate = tree.update(
            nodes[updatedNodeIndex],
            value: updatedB.value,
            aggregate: updatedB.aggregate
        )
        let values = tree.valuesInOrder()

        // Then
        #expect(didUpdate == expectedUpdateResult)
        #expect(values == expectedValues)
    }

    @Test("노드 갱신이 prefix sum을 바꾼다")
    func updateChangesPrefixSums() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let a = (value: "a", aggregate: 10.0)
        let b = (value: "b", aggregate: 20.0)
        let c = (value: "c", aggregate: 30.0)
        let updatedB = (value: "updated-b", aggregate: 50.0)
        let entries: [(value: String, aggregate: Double)] = [a, b, c]
        let updatedNodeIndex = 1
        let queriedIndices = [0, 1, 2, 3]
        let expectedPrefixSums = [
            0.0,
            a.aggregate,
            a.aggregate + updatedB.aggregate,
            a.aggregate + updatedB.aggregate + c.aggregate,
        ]
        let nodes = insertEntries(entries, into: tree)

        // When
        tree.update(
            nodes[updatedNodeIndex],
            value: updatedB.value,
            aggregate: updatedB.aggregate
        )
        let prefixSums = queriedIndices.map { tree.prefixSum(upTo: $0) }

        // Then
        #expect(prefixSums == expectedPrefixSums)
    }

    @Test("노드 갱신이 Y 위치 조회를 바꾼다")
    func updateChangesPrefixPositionLookup() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let a = (value: "a", aggregate: 10.0)
        let b = (value: "b", aggregate: 20.0)
        let c = (value: "c", aggregate: 30.0)
        let updatedB = (value: "updated-b", aggregate: 50.0)
        let entries: [(value: String, aggregate: Double)] = [a, b, c]
        let updatedNodeIndex = 1
        let positions = [59.999, 60]
        let expectedPositionValues: [String?] = [updatedB.value, c.value]
        let expectedPositionIndices: [Int?] = [1, 2]
        let nodes = insertEntries(entries, into: tree)

        // When
        tree.update(
            nodes[updatedNodeIndex],
            value: updatedB.value,
            aggregate: updatedB.aggregate
        )
        let positionValues = positions.map { tree.node(containingPrefixPosition: $0)?.value }
        let positionIndices = positions.map { tree.index(containingPrefixPosition: $0) }

        // Then
        #expect(positionValues == expectedPositionValues)
        #expect(positionIndices == expectedPositionIndices)
    }

    @Test("index 삭제가 제거 값을 반환하고 순서를 갱신한다")
    func removeAtIndexReturnsRemovedValueAndUpdatesOrder() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
        ]
        let removalIndex = 1
        let expectedRemovedValue: String? = "b"
        let expectedValues = ["a", "c"]
        insertEntries(entries, into: tree)

        // When
        let removedValue = tree.remove(at: removalIndex)
        let values = tree.valuesInOrder()

        // Then
        #expect(removedValue == expectedRemovedValue)
        #expect(values == expectedValues)
    }

    @Test("노드 삭제가 제거 값을 반환하고 순서를 갱신한다")
    func removeNodeReturnsRemovedValueAndUpdatesOrder() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
        ]
        let removedNodeIndex = 1
        let expectedRemovedValue: String? = "b"
        let expectedValues = ["a", "c"]
        let nodes = insertEntries(entries, into: tree)

        // When
        let removedValue = tree.remove(node: nodes[removedNodeIndex])
        let values = tree.valuesInOrder()

        // Then
        #expect(removedValue == expectedRemovedValue)
        #expect(values == expectedValues)
    }

    @Test("전체 삭제가 트리 상태를 비운다")
    func removeAllClearsTreeState() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
        ]
        let selectedIndex = 0
        let queriedPosition = 0.0
        let expectedValues: [String] = []
        let expectedTotalAggregate = 0.0
        let expectedSelectedValue: String? = nil
        let expectedPositionValue: String? = nil
        let expectedPositionIndex: Int? = nil
        insertEntries(entries, into: tree)

        // When
        tree.removeAll()
        let values = tree.valuesInOrder()
        let totalAggregate = tree.totalAggregate
        let selectedValue = tree.select(selectedIndex)?.value
        let positionValue = tree.node(containingPrefixPosition: queriedPosition)?.value
        let positionIndex = tree.index(containingPrefixPosition: queriedPosition)

        // Then
        #expect(values == expectedValues)
        #expect(totalAggregate == expectedTotalAggregate)
        #expect(selectedValue == expectedSelectedValue)
        #expect(positionValue == expectedPositionValue)
        #expect(positionIndex == expectedPositionIndex)
    }
}
