import Testing

@testable import SlopadEditorDataStructure

@Suite("prefix sum red-black tree 순서 조회")
struct PrefixSumRedBlackTreeOrderQueryTests {
    @Test("select가 index 위치의 노드를 반환한다")
    func selectReturnsNodeAtIndex() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
        ]
        let selectedIndex = 1
        let expectedValue: String? = "b"
        let expectedAggregate: Double? = 20
        insertEntries(entries, into: tree)

        // When
        let selectedNode = tree.select(selectedIndex)

        // Then
        #expect(selectedNode?.value == expectedValue)
        #expect(selectedNode?.aggregate == expectedAggregate)
    }

    @Test("rank가 노드의 현재 index를 반환한다")
    func rankReturnsIndexForNode() {
        // Given
        let tree = PrefixSumRedBlackTree<String>()
        let entries: [(value: String, aggregate: Double)] = [
            (value: "a", aggregate: 10),
            (value: "b", aggregate: 20),
            (value: "c", aggregate: 30),
        ]
        let rankedNodeIndex = 2
        let expectedRank: Int? = 2
        let nodes = insertEntries(entries, into: tree)

        // When
        let rank = tree.rank(of: nodes[rankedNodeIndex])

        // Then
        #expect(rank == expectedRank)
    }
}
