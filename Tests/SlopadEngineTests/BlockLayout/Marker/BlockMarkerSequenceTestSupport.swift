@testable import SlopadEditorBlockLayout
import SlopadCoreModel

func orderedMarkerBlock(
    id: BlockID,
    restartNumber: Int? = nil
) -> Block {
    Block(
        id: id,
        kind: .orderedListItem(restartNumber: restartNumber),
        content: BlockContent(text: id.rawValue)
    )
}

func markerKinds(
    _ markerSequence: BlockMarkerSequence,
    visibleIndex: VisibleBlockIndex
) -> [BlockMarkerKind] {
    visibleIndex.entriesSnapshot().map { visible in
        markerSequence.markerKind(for: visible.blockID)
    }
}
