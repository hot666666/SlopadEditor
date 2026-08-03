import SlopadCoreModel

// MARK: - DebugSnapshotRevisionComparison

struct EditorSnapshotRevisionComparison: Hashable, Sendable {
    let hasPreviousRevision: Bool
    let documentRevision: Int
    let compositionRevision: Int
    let textLayoutRevision: Int
    let documentChanged: Bool
    let compositionChanged: Bool
    let textLayoutChanged: Bool
    let widthChanged: Bool
    let visibleSequenceChanged: Bool
}

extension EditorSnapshotRevision {
    func comparison(from previous: EditorSnapshotRevision?) -> EditorSnapshotRevisionComparison {
        EditorSnapshotRevisionComparison(
            hasPreviousRevision: previous != nil,
            documentRevision: documentRevision,
            compositionRevision: compositionRevision,
            textLayoutRevision: textLayoutRevision,
            documentChanged: previous?.documentRevision != documentRevision,
            compositionChanged: previous?.compositionRevision != compositionRevision,
            textLayoutChanged: previous?.textLayoutRevision != textLayoutRevision,
            widthChanged: previous?.widthRevision != widthRevision,
            visibleSequenceChanged: previous?.visibleSequenceRevision != visibleSequenceRevision
        )
    }
}
