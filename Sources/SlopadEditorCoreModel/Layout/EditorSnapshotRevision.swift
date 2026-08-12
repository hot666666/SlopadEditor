// MARK: - EditorSnapshotRevision

public struct EditorSnapshotRevision: Hashable, Sendable {
    package let documentRevision: Int
    package let compositionRevision: Int
    package let textLayoutRevision: Int
    package let widthRevision: Int
    package let visibleSequenceRevision: Int

    package init(
        documentRevision: Int,
        compositionRevision: Int,
        textLayoutRevision: Int,
        widthRevision: Int,
        visibleSequenceRevision: Int
    ) {
        self.documentRevision = documentRevision
        self.compositionRevision = compositionRevision
        self.textLayoutRevision = textLayoutRevision
        self.widthRevision = widthRevision
        self.visibleSequenceRevision = visibleSequenceRevision
    }
}
