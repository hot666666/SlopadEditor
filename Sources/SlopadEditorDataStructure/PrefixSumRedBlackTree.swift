package final class PrefixSumRedBlackTree<Value>: @unchecked Sendable {

    // MARK: - Node

    package final class Node: @unchecked Sendable {
        fileprivate var valueStorage: Value
        fileprivate var aggregateStorage: Double
        fileprivate var subtreeAggregate: Double
        fileprivate var subtreeCount: Int

        fileprivate var color: Color
        fileprivate var left: Node?
        fileprivate var right: Node?
        fileprivate weak var parent: Node?

        fileprivate weak var owner: PrefixSumRedBlackTree<Value>?

        // MARK: - Owner Access

        var value: Value {
            valueStorage
        }

        var aggregate: Double {
            aggregateStorage
        }

        // MARK: - Lifecycle

        fileprivate init(
            value: Value,
            aggregate: Double,
            color: Color = .red,
            owner: PrefixSumRedBlackTree<Value>
        ) {
            self.valueStorage = value
            self.aggregateStorage = aggregate
            self.color = color
            self.subtreeCount = 1
            self.subtreeAggregate = aggregate
            self.owner = owner
        }
    }

    // MARK: - Tree Repair Types

    fileprivate enum Color {
        case red
        case black
    }

    fileprivate enum ChildSide {
        case left
        case right

        var opposite: ChildSide {
            switch self {
            case .left: return .right
            case .right: return .left
            }
        }
    }

    fileprivate struct DeletionRepairContext {
        var child: Node?
        var parent: Node?
        var childSide: ChildSide?
        var removedColor: Color
    }

    // MARK: - State

    private var root: Node?

    // MARK: - Metrics

    #if SLOPAD_TREE_METRICS
        package private(set) var visitCount: Int = 0
        package func resetVisitCount() {
            visitCount = 0
        }
    #endif

    // MARK: - Lifecycle

    package init() {}

    // MARK: - Basic Queries

    package var count: Int {
        Self.count(root)
    }

    package var totalAggregate: Double {
        Self.aggregate(root)
    }

    func valuesInOrder() -> [Value] {
        var values: [Value] = []
        values.reserveCapacity(count)
        forEachNodeInOrder { node in
            values.append(node.valueStorage)
        }
        return values
    }

    // MARK: - Mutation

    func removeAll() {
        detachSubtree(root)
        root = nil
    }

    @discardableResult
    package func replaceAll(with entries: [(value: Value, aggregate: Double)]) -> [Node] {
        detachSubtree(root)
        guard !entries.isEmpty else {
            root = nil
            return []
        }

        let nodes = entries.map {
            Node(value: $0.value, aggregate: $0.aggregate, color: .black, owner: self)
        }
        let built = buildBalancedSubtree(nodes, in: nodes.indices, parent: nil)
        root = built.node
        root?.color = .black
        return nodes
    }

    @discardableResult
    package func insert(value: Value, aggregate: Double, at index: Int) -> Node {
        let boundedIndex = max(0, min(index, count))
        let inserted = Node(value: value, aggregate: aggregate, owner: self)

        attach(inserted, at: boundedIndex)
        refreshPath(from: inserted.parent)
        restoreRedBlackProperties(afterInserting: inserted)
        return inserted
    }

    @discardableResult
    func remove(at index: Int) -> Value? {
        guard let node = select(index) else { return nil }
        return remove(node: node)
    }

    @discardableResult
    package func remove(node: Node) -> Value? {
        guard rankIfAttached(node) != nil else { return nil }
        let removed = node.valueStorage
        delete(node)
        detach(node)
        return removed
    }

    @discardableResult
    package func update(_ node: Node, value: Value, aggregate: Double) -> Bool {
        guard rankIfAttached(node) != nil else { return false }
        node.valueStorage = value
        node.aggregateStorage = aggregate
        refreshPath(from: node)
        return true
    }

    // MARK: - Ordered Lookup

    func select(_ index: Int) -> Node? {
        node(at: index)
    }

    package func value(at index: Int) -> Value? {
        node(at: index)?.valueStorage
    }

    package func value(of node: Node) -> Value? {
        guard rankIfAttached(node) != nil else { return nil }
        return node.valueStorage
    }

    package func rank(of node: Node) -> Int? {
        rankIfAttached(node)
    }

    // MARK: - Prefix Lookup

    func prefixSum(upTo index: Int) -> Double {
        var requestedCount = max(0, min(index, count))
        var cursor = root
        var sum = 0.0

        while let node = cursor, requestedCount > 0 {
            recordVisit()
            let leftCount = Self.count(node.left)
            if requestedCount <= leftCount {
                cursor = node.left
            } else {
                sum += Self.aggregate(node.left)
                if requestedCount == leftCount + 1 {
                    return sum + node.aggregateStorage
                }

                sum += node.aggregateStorage
                requestedCount -= leftCount + 1
                cursor = node.right
            }
        }

        return sum
    }

    package func prefixSum(upTo node: Node) -> Double? {
        guard node.owner === self else { return nil }
        var sum = Self.aggregate(node.left)
        var cursor = node

        while let parent = cursor.parent {
            recordVisit()
            if cursor === parent.right {
                sum += Self.aggregate(parent.left) + parent.aggregateStorage
            }
            cursor = parent
        }

        guard cursor === root else { return nil }
        return sum
    }

    func node(containingPrefixPosition position: Double) -> Node? {
        prefixPositionMatch(containing: position)?.node
    }

    package func value(containingPrefixPosition position: Double) -> Value? {
        prefixPositionMatch(containing: position)?.node.valueStorage
    }

    package func index(containingPrefixPosition position: Double) -> Int? {
        prefixPositionMatch(containing: position)?.index
    }

    package func firstIndexWithPrefixSum(atLeast target: Double) -> Int {
        guard count > 0 else { return 0 }
        if target <= 0 {
            return 0
        }
        if target >= totalAggregate {
            return count
        }

        var cursor = root
        var baseIndex = 0
        var basePrefix = 0.0
        var candidate = count
        while let node = cursor {
            recordVisit()
            let leftCount = Self.count(node.left)
            let leftAggregate = Self.aggregate(node.left)
            let nodeIndex = baseIndex + leftCount
            let nodeTop = basePrefix + leftAggregate
            if target <= nodeTop {
                candidate = nodeIndex
                cursor = node.left
                continue
            }

            let nodeBottom = nodeTop + node.aggregateStorage
            if target <= nodeBottom {
                return nodeIndex + 1
            }

            baseIndex = nodeIndex + 1
            basePrefix = nodeBottom
            cursor = node.right
        }
        return candidate
    }
}

// MARK: - Traversal

extension PrefixSumRedBlackTree {
    fileprivate func node(at index: Int) -> Node? {
        guard index >= 0, index < count else { return nil }

        var target = index
        var cursor = root
        while let node = cursor {
            recordVisit()
            let leftCount = Self.count(node.left)
            if target < leftCount {
                cursor = node.left
            } else if target == leftCount {
                return node
            } else {
                target -= leftCount + 1
                cursor = node.right
            }
        }

        return nil
    }

    fileprivate func rankIfAttached(_ node: Node) -> Int? {
        guard node.owner === self else { return nil }

        var result = Self.count(node.left)
        var cursor: Node? = node
        while let current = cursor {
            recordVisit()
            guard let parent = current.parent else {
                return current === root ? result : nil
            }
            if current === parent.right {
                result += Self.count(parent.left) + 1
            }
            cursor = parent
        }

        return nil
    }

    fileprivate func prefixPositionMatch(containing position: Double) -> (node: Node, index: Int)? {
        guard count > 0 else { return nil }
        if position < 0 {
            guard let first = node(at: 0) else { return nil }
            return (node: first, index: 0)
        }
        guard position < totalAggregate else { return nil }

        var cursor = root
        var localPosition = position
        var baseIndex = 0
        while let node = cursor {
            recordVisit()
            let leftCount = Self.count(node.left)
            let leftAggregate = Self.aggregate(node.left)
            if localPosition < leftAggregate {
                cursor = node.left
                continue
            }

            let nodeUpperBound = leftAggregate + node.aggregateStorage
            if localPosition < nodeUpperBound {
                return (node: node, index: baseIndex + leftCount)
            }

            localPosition -= nodeUpperBound
            baseIndex += leftCount + 1
            cursor = node.right
        }

        return nil
    }

    fileprivate func forEachNodeInOrder(_ body: (Node) -> Void) {
        var stack: [Node] = []
        var cursor = root

        while cursor != nil || !stack.isEmpty {
            while let node = cursor {
                stack.append(node)
                cursor = node.left
            }

            guard let node = stack.popLast() else { return }
            body(node)
            cursor = node.right
        }
    }

    fileprivate func minimum(_ node: Node) -> Node {
        var cursor = node
        while let left = cursor.left {
            recordVisit()
            cursor = left
        }
        return cursor
    }

    fileprivate func buildBalancedSubtree(
        _ nodes: [Node],
        in range: Range<Int>,
        parent: Node?
    ) -> (node: Node?, blackHeight: Int) {
        guard !range.isEmpty else {
            return (nil, 1)
        }

        let middle = range.lowerBound + range.count / 2
        let node = nodes[middle]
        let left = buildBalancedSubtree(
            nodes,
            in: range.lowerBound..<middle,
            parent: node
        )
        let right = buildBalancedSubtree(
            nodes,
            in: (middle + 1)..<range.upperBound,
            parent: node
        )

        node.parent = parent
        node.left = left.node
        node.right = right.node
        node.owner = self
        node.color = .black

        let heightDelta = left.blackHeight - right.blackHeight
        assert(abs(heightDelta) <= 1)
        let blackHeight: Int
        if heightDelta > 0 {
            node.left?.color = .red
            blackHeight = right.blackHeight + 1
        } else if heightDelta < 0 {
            node.right?.color = .red
            blackHeight = left.blackHeight + 1
        } else {
            blackHeight = left.blackHeight + 1
        }

        Self.refresh(node)
        return (node, blackHeight)
    }
}

// MARK: - Cached Subtree Values

extension PrefixSumRedBlackTree {
    @inline(__always)
    fileprivate func recordVisit() {
        #if SLOPAD_TREE_METRICS
            visitCount += 1
        #endif
    }

    fileprivate static func count(_ node: Node?) -> Int {
        node?.subtreeCount ?? 0
    }

    fileprivate static func aggregate(_ node: Node?) -> Double {
        node?.subtreeAggregate ?? 0
    }

    fileprivate static func refresh(_ node: Node?) {
        guard let node else { return }
        node.subtreeCount = 1 + count(node.left) + count(node.right)
        node.subtreeAggregate = node.aggregateStorage + aggregate(node.left) + aggregate(node.right)
    }

    fileprivate func refreshPath(from node: Node?) {
        var cursor = node
        while let node = cursor {
            Self.refresh(node)
            cursor = node.parent
        }
    }
}

// MARK: - Red-Black Tree Operations

extension PrefixSumRedBlackTree {
    fileprivate static func color(_ node: Node?) -> Color {
        node?.color ?? .black
    }

    fileprivate static func child(of node: Node?, on side: ChildSide) -> Node? {
        switch side {
        case .left:
            return node?.left
        case .right:
            return node?.right
        }
    }

    fileprivate static func side(of child: Node?, in parent: Node) -> ChildSide {
        child === parent.left ? .left : .right
    }

    fileprivate func rotate(_ node: Node, raising childSide: ChildSide) {
        switch childSide {
        case .left:
            rotateRight(node)
        case .right:
            rotateLeft(node)
        }
    }

    fileprivate func transplant(_ source: Node, with replacement: Node?) {
        if source.parent == nil {
            root = replacement
        } else if source === source.parent?.left {
            source.parent?.left = replacement
        } else {
            source.parent?.right = replacement
        }
        replacement?.parent = source.parent
    }

    fileprivate func rotateLeft(_ node: Node) {
        guard let pivot = node.right else { return }

        node.right = pivot.left
        pivot.left?.parent = node

        pivot.parent = node.parent
        if node.parent == nil {
            root = pivot
        } else if node === node.parent?.left {
            node.parent?.left = pivot
        } else {
            node.parent?.right = pivot
        }

        pivot.left = node
        node.parent = pivot

        Self.refresh(node)
        Self.refresh(pivot)
        refreshPath(from: pivot.parent)
    }

    fileprivate func rotateRight(_ node: Node) {
        guard let pivot = node.left else { return }

        node.left = pivot.right
        pivot.right?.parent = node

        pivot.parent = node.parent
        if node.parent == nil {
            root = pivot
        } else if node === node.parent?.right {
            node.parent?.right = pivot
        } else {
            node.parent?.left = pivot
        }

        pivot.right = node
        node.parent = pivot

        Self.refresh(node)
        Self.refresh(pivot)
        refreshPath(from: pivot.parent)
    }
}

// MARK: - Insertion

extension PrefixSumRedBlackTree {
    fileprivate func attach(_ inserted: Node, at index: Int) {
        guard let root else {
            inserted.color = .black
            self.root = inserted
            return
        }

        var cursor = root
        var target = index
        while true {
            recordVisit()
            let leftCount = Self.count(cursor.left)
            if target <= leftCount {
                if let left = cursor.left {
                    cursor = left
                } else {
                    cursor.left = inserted
                    inserted.parent = cursor
                    return
                }
            } else {
                target -= leftCount + 1
                if let right = cursor.right {
                    cursor = right
                } else {
                    cursor.right = inserted
                    inserted.parent = cursor
                    return
                }
            }
        }
    }

    fileprivate func restoreRedBlackProperties(afterInserting inserted: Node) {
        var node = inserted
        while Self.color(node.parent) == .red {
            guard let parent = node.parent, let grandparent = parent.parent else { break }

            let parentSide = Self.side(of: parent, in: grandparent)
            let uncleSide = parentSide.opposite
            let uncle = Self.child(of: grandparent, on: uncleSide)
            if Self.color(uncle) == .red {
                parent.color = .black
                uncle?.color = .black
                grandparent.color = .red
                node = grandparent
                continue
            }

            if Self.side(of: node, in: parent) == uncleSide {
                node = parent
                rotate(node, raising: uncleSide)
            }

            node.parent?.color = .black
            node.parent?.parent?.color = .red
            if let grandparent = node.parent?.parent {
                rotate(grandparent, raising: parentSide)
            }
        }

        root?.color = .black
    }
}

// MARK: - Deletion

extension PrefixSumRedBlackTree {
    fileprivate func delete(_ node: Node) {
        let repair = deletionRepairContext(removing: node)
        if repair.removedColor == .black {
            restoreRedBlackPropertiesAfterDeletion(
                node: repair.child,
                parent: repair.parent,
                childSide: repair.childSide
            )
        }
        root?.color = .black
    }

    fileprivate func deletionRepairContext(removing node: Node) -> DeletionRepairContext {
        if node.left == nil {
            return deleteNodeWithAtMostOneChild(node, replacement: node.right)
        }
        if node.right == nil {
            return deleteNodeWithAtMostOneChild(node, replacement: node.left)
        }
        return deleteNodeWithTwoChildren(node)
    }

    fileprivate func deleteNodeWithAtMostOneChild(
        _ node: Node,
        replacement: Node?
    ) -> DeletionRepairContext {
        let parent = node.parent
        let childSide = parent.map { Self.side(of: node, in: $0) }
        let removedColor = node.color
        transplant(node, with: replacement)
        refreshPath(from: parent)
        return DeletionRepairContext(
            child: replacement,
            parent: parent,
            childSide: childSide,
            removedColor: removedColor
        )
    }

    fileprivate func deleteNodeWithTwoChildren(_ node: Node) -> DeletionRepairContext {
        guard let right = node.right else {
            return deleteNodeWithAtMostOneChild(node, replacement: node.left)
        }

        let successor = minimum(right)
        let removedColor = successor.color
        let movedChild = successor.right
        let repairParent: Node?
        let repairSide: ChildSide?

        if successor.parent === node {
            repairParent = successor
            repairSide = .right
        } else {
            let successorParent = successor.parent
            repairParent = successorParent
            repairSide = successorParent.map { Self.side(of: successor, in: $0) }
            transplant(successor, with: successor.right)
            refreshPath(from: successorParent)

            successor.right = node.right
            successor.right?.parent = successor
        }

        transplant(node, with: successor)
        successor.left = node.left
        successor.left?.parent = successor
        successor.color = node.color

        Self.refresh(successor)
        refreshPath(from: successor.parent)

        return DeletionRepairContext(
            child: movedChild,
            parent: repairParent,
            childSide: repairSide,
            removedColor: removedColor
        )
    }

    fileprivate func restoreRedBlackPropertiesAfterDeletion(
        node child: Node?,
        parent initialParent: Node?,
        childSide initialChildSide: ChildSide?
    ) {
        var node = child
        var parent = initialParent
        var childSide = initialChildSide

        while node !== root && Self.color(node) == .black {
            guard let currentParent = parent else { break }
            let missingSide = childSide ?? Self.side(of: node, in: currentParent)
            let siblingSide = missingSide.opposite
            var sibling = Self.child(of: currentParent, on: siblingSide)

            if Self.color(sibling) == .red {
                sibling?.color = .black
                currentParent.color = .red
                rotate(currentParent, raising: siblingSide)
                sibling = Self.child(of: currentParent, on: siblingSide)
            }

            let nearNephew = Self.child(of: sibling, on: missingSide)
            let farNephew = Self.child(of: sibling, on: siblingSide)
            if Self.color(nearNephew) == .black && Self.color(farNephew) == .black {
                sibling?.color = .red
                node = currentParent
                parent = node?.parent
                childSide = nil
                continue
            }

            if Self.color(farNephew) == .black {
                Self.child(of: sibling, on: missingSide)?.color = .black
                sibling?.color = .red
                if let sibling {
                    rotate(sibling, raising: missingSide)
                }
                sibling = Self.child(of: currentParent, on: siblingSide)
            }

            sibling?.color = currentParent.color
            currentParent.color = .black
            Self.child(of: sibling, on: siblingSide)?.color = .black
            rotate(currentParent, raising: siblingSide)
            node = root
            parent = nil
            childSide = nil
        }

        node?.color = .black
        root?.color = .black
    }
}

// MARK: - Detach

extension PrefixSumRedBlackTree {
    fileprivate func detachSubtree(_ node: Node?) {
        guard let node else { return }
        let left = node.left
        let right = node.right
        detachSubtree(left)
        detachSubtree(right)
        detach(node)
    }

    fileprivate func detach(_ node: Node) {
        node.left = nil
        node.right = nil
        node.parent = nil
        node.owner = nil
        node.subtreeCount = 1
        node.subtreeAggregate = node.aggregateStorage
        node.color = .black
    }
}

// MARK: - Invariant Validation

#if DEBUG
    extension PrefixSumRedBlackTree {
        func validateInvariantsForTesting() -> Bool {
            guard root?.color != .red else { return false }
            var isValid = true

            func validate(_ node: Node?, parent: Node?) -> (
                count: Int, aggregate: Double, blackHeight: Int
            ) {
                guard let node else { return (0, 0, 1) }
                guard node.parent === parent else {
                    isValid = false
                    return (0, 0, 0)
                }
                guard node.owner === self else {
                    isValid = false
                    return (0, 0, 0)
                }

                if node.color == .red {
                    if Self.color(node.left) != .black || Self.color(node.right) != .black {
                        isValid = false
                    }
                }

                let left = validate(node.left, parent: node)
                let right = validate(node.right, parent: node)
                if left.blackHeight != right.blackHeight {
                    isValid = false
                }

                let expectedCount = 1 + left.count + right.count
                let expectedAggregate = node.aggregateStorage + left.aggregate + right.aggregate
                if node.subtreeCount != expectedCount {
                    isValid = false
                }
                if abs(node.subtreeAggregate - expectedAggregate) > 0.000_000_1 {
                    isValid = false
                }

                return (
                    expectedCount,
                    expectedAggregate,
                    left.blackHeight + (node.color == .black ? 1 : 0)
                )
            }

            _ = validate(root, parent: nil)
            return isValid
        }

        func heightForTesting() -> Int {
            func height(_ node: Node?) -> Int {
                guard let node else { return 0 }
                return 1 + max(height(node.left), height(node.right))
            }

            return height(root)
        }
    }
#endif
