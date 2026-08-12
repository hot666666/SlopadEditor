@testable import SlopadEditorBlockLayout
import SlopadCoreModel

typealias BlockLayoutTestInput = (
    contentSnapshot: EffectiveDocumentSnapshot,
    visibleIndex: VisibleBlockIndex,
    availableWidth: Double,
    widthRevision: Int?
)

func makeBlockLayoutTestInput(
    document: Document,
    composition: TextComposition? = nil,
    visibleIndex: VisibleBlockIndex? = nil,
    availableWidth: Double,
    widthRevision: Int? = nil
) -> BlockLayoutTestInput {
    (
        EffectiveDocumentSnapshot(document: document, composition: composition),
        visibleIndex ?? VisibleBlockIndex(document: document),
        availableWidth,
        widthRevision
    )
}

func runBlockLayoutPass(
    _ blockLayout: inout BlockLayout,
    input: BlockLayoutTestInput,
    textLayouter: any BlockMeasuring
) -> EditorSnapshotRevision {
    let revision = blockLayout.layout(
        contentSnapshot: input.contentSnapshot,
        visibleIndex: input.visibleIndex,
        availableWidth: input.availableWidth,
        widthRevision: input.widthRevision,
        textLayouter: textLayouter
    )
    blockLayout.updateLayoutState(
        visibleIndex: input.visibleIndex,
        markerSequence: BlockMarkerSequence(
            document: input.contentSnapshot.document,
            visibleIndex: input.visibleIndex
        ),
        widthRevision: input.widthRevision ?? Int(truncatingIfNeeded: input.availableWidth.bitPattern)
    )
    return revision
}

func runBlockLayoutIncrementalPass(
    _ blockLayout: inout BlockLayout,
    input: BlockLayoutTestInput,
    blockIDs: Set<BlockID>,
    textLayouter: any BlockMeasuring
) -> EditorSnapshotRevision? {
    let revision = blockLayout.applyIncrementalLayout(
        contentSnapshot: input.contentSnapshot,
        visibleIndex: input.visibleIndex,
        availableWidth: input.availableWidth,
        widthRevision: input.widthRevision,
        changeSet: BlockLayoutChangeSet(updatedBlockIDs: blockIDs),
        textLayouter: textLayouter
    )
    if revision != nil {
        blockLayout.updateLayoutState(
            visibleIndex: input.visibleIndex,
            markerSequence: BlockMarkerSequence(
                document: input.contentSnapshot.document,
                visibleIndex: input.visibleIndex
            ),
            widthRevision: input.widthRevision
                ?? Int(truncatingIfNeeded: input.availableWidth.bitPattern)
        )
    }
    return revision
}
