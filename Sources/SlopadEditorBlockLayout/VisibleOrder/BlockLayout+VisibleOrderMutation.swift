import SlopadCoreModel

// MARK: - Visible Order Mutation

extension BlockLayout {
    func applyVisibleOrderMutation(
        mutations: [BlockLayoutMutation],
        document: Document,
        visibleIndex: VisibleBlockIndex,
        changeSet: inout BlockLayoutChangeSet
    ) -> Bool {
        for mutation in mutations {
            switch mutation {
            case .splitBlock(let original, let created):
                guard
                    applyVisibleOrderSplit(
                        original: original,
                        created: created,
                        document: document,
                        visibleIndex: visibleIndex,
                        changeSet: &changeSet
                    )
                else {
                    return false
                }

            case .mergeBlocks(let target, let source):
                guard
                    applyVisibleOrderMerge(
                        target: target,
                        source: source,
                        visibleIndex: visibleIndex,
                        changeSet: &changeSet
                    )
                else {
                    return false
                }

            case .deleteBlocks(let blockIDs):
                let removed = visibleIndex.remove(blockIDs: blockIDs)
                changeSet.removedBlockIDs.append(contentsOf: removed.map(\.blockID))

            case .resetDocumentToEmptyParagraph(let blockID):
                resetVisibleOrderToEmptyParagraph(
                    blockID: blockID,
                    visibleIndex: visibleIndex,
                    changeSet: &changeSet
                )

            case .refreshMarker:
                continue

            case .relocateSubtrees(let blockIDs):
                guard
                    relocateVisibleOrderSpans(
                        blockIDs: blockIDs,
                        document: document,
                        visibleIndex: visibleIndex,
                        changeSet: &changeSet
                    )
                else {
                    return false
                }
            }
        }
        return true
    }

    private func resetVisibleOrderToEmptyParagraph(
        blockID: BlockID,
        visibleIndex: VisibleBlockIndex,
        changeSet: inout BlockLayoutChangeSet
    ) {
        let existingBlockIDs = visibleIndex.entriesSnapshot().map(\.blockID)
            .filter { $0 != blockID }
        if !existingBlockIDs.isEmpty {
            changeSet.removedBlockIDs.append(contentsOf: existingBlockIDs)
        }
        visibleIndex.removeAll()
        _ = visibleIndex.insert(
            VisibleBlock(blockID: blockID, depth: 0, parentID: nil),
            at: 0
        )
        changeSet.insertedBlockIDs.append(blockID)
    }
}
