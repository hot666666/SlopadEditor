import SlopadCoreModel

// MARK: - Content Projection

extension BlockLayout {
    package func effectiveBlock(
        for blockID: BlockID,
        document: Document,
        composition: TextComposition?
    ) -> Block? {
        EffectiveDocumentSnapshot(document: document, composition: composition)
            .block(for: blockID)
    }
}
