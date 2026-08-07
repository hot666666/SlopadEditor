import SlopadCoreModel

// MARK: - Reveal

extension BlockLayout {
    package mutating func revealFrame(
        for blockID: BlockID,
        document: Document,
        composition: TextComposition?,
        viewport: EditorViewport,
        textLayouter: any BlockMeasuring
    ) -> EditorRect? {
        let contentSnapshot = EffectiveDocumentSnapshot(
            document: document,
            composition: composition
        )
        measureBlockIfNeeded(
            blockID: blockID,
            contentSnapshot: contentSnapshot,
            availableWidth: viewport.width,
            textLayouter: textLayouter
        )
        return blockGeometry(for: blockID)?.frame(width: viewport.width)
    }
}
