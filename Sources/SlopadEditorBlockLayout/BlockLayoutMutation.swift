import SlopadCoreModel

// MARK: - BlockLayoutMutation

package enum BlockLayoutMutation {
    case splitBlock(original: BlockID, created: BlockID)
    case mergeBlocks(target: BlockID, source: BlockID)
    case deleteBlocks(blockIDs: [BlockID])
    case resetDocumentToEmptyParagraph(blockID: BlockID)
    case relocateSubtrees(blockIDs: [BlockID])
    case refreshMarker
}
