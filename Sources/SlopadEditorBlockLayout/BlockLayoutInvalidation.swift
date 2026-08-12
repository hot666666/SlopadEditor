import SlopadCoreModel

// MARK: - BlockLayoutInvalidation

package struct BlockLayoutInvalidation {
    private(set) var blockIDs: Set<BlockID>
    private(set) var layoutGeometryChanged: Bool
    private(set) var mutations: [BlockLayoutMutation]

    var visibleSequenceChanged: Bool {
        mutations.contains { $0.changesVisibleSequence }
    }

    package init(
        blockIDs: Set<BlockID> = [],
        layoutGeometryChanged: Bool = false,
        mutations: [BlockLayoutMutation] = []
    ) {
        self.blockIDs = blockIDs
        self.layoutGeometryChanged = layoutGeometryChanged
        self.mutations = mutations
    }

    mutating func formUnion(_ other: BlockLayoutInvalidation) {
        blockIDs.formUnion(other.blockIDs)
        layoutGeometryChanged = layoutGeometryChanged || other.layoutGeometryChanged
        mutations.append(contentsOf: other.mutations)
    }

}

extension BlockLayoutMutation {
    fileprivate var changesVisibleSequence: Bool {
        switch self {
        case .splitBlock, .mergeBlocks, .resetDocumentToEmptyParagraph:
            return true
        case .deleteBlocks(let blockIDs), .relocateSubtrees(let blockIDs):
            return !blockIDs.isEmpty
        case .refreshMarker:
            return false
        }
    }
}
