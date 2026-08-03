import SlopadCoreModel

// MARK: - Snapshot Revision

extension BlockLayout {
    func makeRevision(
        contentSnapshot: EffectiveDocumentSnapshot,
        visibleIndex: VisibleBlockIndex,
        availableWidth: Double,
        widthRevision: Int?
    ) -> EditorSnapshotRevision {
        EditorSnapshotRevision(
            documentRevision: contentSnapshot.revision,
            compositionRevision: contentSnapshot.compositionRevision,
            textLayoutRevision: textLayoutRevision,
            widthRevision:
                widthRevision ?? Int(truncatingIfNeeded: availableWidth.bitPattern),
            visibleSequenceRevision: visibleIndex.revision
        )
    }
}
