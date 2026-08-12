import SlopadCoreModel
import SlopadEditorDataStructure

// MARK: - RBTreeBlockHeightIndexStorage

final class RBTreeBlockHeightIndexStorage {
    private typealias Tree = PrefixSumRedBlackTree<BlockHeightIndexStorage.Entry>
    private typealias Node = Tree.Node

    private let tree: Tree
    private var nodesByBlockID: [BlockID: Node]

    init(entries: [BlockHeightIndexStorage.Entry]) {
        self.tree = Tree()
        self.nodesByBlockID = [:]

        let nodes = tree.replaceAll(
            with: entries.map { block in
                (value: block, aggregate: block.height)
            }
        )
        nodesByBlockID.reserveCapacity(entries.count)
        for (block, node) in zip(entries, nodes) {
            nodesByBlockID[block.blockID] = node
        }
    }

    var count: Int {
        tree.count
    }

    var totalHeight: Double {
        tree.totalAggregate
    }

    func entry(at index: Int) -> BlockHeightIndexStorage.Entry? {
        tree.value(at: index)
    }

    func index(of blockID: BlockID) -> Int? {
        guard let node = node(for: blockID) else { return nil }
        return tree.rank(of: node)
    }

    func topY(for blockID: BlockID) -> Double? {
        guard let node = node(for: blockID) else { return nil }
        return tree.prefixSum(upTo: node)
    }

    func blockID(atY yOffset: Double) -> BlockID? {
        tree.value(containingPrefixPosition: yOffset)?.blockID
    }

    func visibleRange(yOffset: Double, viewportHeight: Double) -> Range<Int> {
        guard viewportHeight > 0, count > 0 else { return 0..<0 }

        let startY = max(0, yOffset)
        guard startY < totalHeight else { return count..<count }

        let start = tree.index(containingPrefixPosition: startY) ?? count
        let end = min(count, tree.firstIndexWithPrefixSum(atLeast: startY + viewportHeight))
        return start..<max(start, end)
    }

    func insert(_ item: BlockHeightIndexStorage.Entry, at index: Int) {
        guard node(for: item.blockID) == nil else { return }
        let node = tree.insert(value: item, aggregate: item.height, at: index)
        nodesByBlockID[item.blockID] = node
    }

    @discardableResult
    func remove(blockID: BlockID) -> BlockHeightIndexStorage.Entry? {
        guard let node = nodesByBlockID.removeValue(forKey: blockID) else { return nil }
        return tree.remove(node: node)
    }

    func updateHeight(blockID: BlockID, height: Double) {
        guard let node = node(for: blockID) else { return }
        tree.update(
            node, value: BlockHeightIndexStorage.Entry(blockID: blockID, height: height),
            aggregate: height)
    }

    func validateInvariantsForTesting() -> Bool {
        guard tree.count == nodesByBlockID.count else { return false }

        var seenRanks: Set<Int> = []
        for (blockID, node) in nodesByBlockID {
            guard tree.value(of: node)?.blockID == blockID else { return false }
            guard let rank = tree.rank(of: node) else { return false }
            guard seenRanks.insert(rank).inserted else { return false }
        }

        return true
    }

    private func node(for blockID: BlockID) -> Node? {
        nodesByBlockID[blockID]
    }
}

#if SLOPAD_TREE_METRICS
    extension RBTreeBlockHeightIndexStorage {
        var visitCount: Int {
            tree.visitCount
        }

        func resetVisitCount() {
            tree.resetVisitCount()
        }
    }
#endif
