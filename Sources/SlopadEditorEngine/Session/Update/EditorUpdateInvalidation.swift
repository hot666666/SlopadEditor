import SlopadCoreModel

// MARK: - EditorUpdateInvalidation

struct EditorUpdateInvalidation {
    var blockIDs: Set<BlockID>
    var visibleSequenceChanged: Bool
    var layoutGeometryChanged: Bool

    init(
        blockIDs: Set<BlockID> = [],
        visibleSequenceChanged: Bool = false,
        layoutGeometryChanged: Bool = false
    ) {
        self.blockIDs = blockIDs
        self.visibleSequenceChanged = visibleSequenceChanged
        self.layoutGeometryChanged = layoutGeometryChanged
    }

    mutating func formUnion(_ other: EditorUpdateInvalidation) {
        blockIDs.formUnion(other.blockIDs)
        visibleSequenceChanged = visibleSequenceChanged || other.visibleSequenceChanged
        layoutGeometryChanged = layoutGeometryChanged || other.layoutGeometryChanged
    }

}
