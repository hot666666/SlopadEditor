import Testing

@testable import SlopadEditorDataStructure

@discardableResult
func insertEntries<Value>(
    _ entries: [(value: Value, aggregate: Double)],
    into tree: PrefixSumRedBlackTree<Value>
) -> [PrefixSumRedBlackTree<Value>.Node] {
    entries.enumerated().map { index, entry in
        tree.insert(value: entry.value, aggregate: entry.aggregate, at: index)
    }
}

func redBlackHeightBound(nodeCount: Int) -> Int {
    guard nodeCount > 0 else { return 0 }

    var powerOfTwo = 1
    var exponent = 0
    while powerOfTwo < nodeCount + 1 {
        powerOfTwo *= 2
        exponent += 1
    }
    return 2 * exponent
}

func assertRedBlackInvariantsHold<Value>(
    _ tree: PrefixSumRedBlackTree<Value>,
    context: String
) {
    #if DEBUG
        #expect(tree.validateInvariantsForTesting(), "red-black invariant failed \(context)")
    #endif
}

func assertTreeHeightStaysWithinRedBlackBound<Value>(
    _ tree: PrefixSumRedBlackTree<Value>,
    context: String
) {
    #if DEBUG
        #expect(
            tree.heightForTesting() <= redBlackHeightBound(nodeCount: tree.count),
            "tree height exceeded red-black bound \(context)"
        )
    #endif
}
