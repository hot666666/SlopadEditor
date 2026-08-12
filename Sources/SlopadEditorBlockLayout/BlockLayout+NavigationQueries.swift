import SlopadCoreModel

// MARK: - Navigation Queries

extension BlockLayout {
    package func visibleBlockID(
        relativeTo blockID: BlockID,
        by offset: Int,
        document: Document
    ) -> BlockID? {
        let visible = currentVisibleIndex(document: document)
        guard let index = visible.index(of: blockID) else { return nil }
        return visible.entry(at: index + offset)?.blockID
    }
}
