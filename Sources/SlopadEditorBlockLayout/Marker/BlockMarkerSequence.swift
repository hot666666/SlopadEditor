import SlopadCoreModel

// MARK: - BlockMarkerSequence

struct BlockMarkerSequence {
    var markerKindByBlockID: [BlockID: BlockMarkerKind]
    var containsOrderedMarkers: Bool

    init(document: Document, visibleIndex: VisibleBlockIndex) {
        markerKindByBlockID = [:]
        markerKindByBlockID.reserveCapacity(visibleIndex.count)
        containsOrderedMarkers = false
        var previousSiblingMarkerByDepth: [Int: BlockMarkerKind] = [:]

        for visible in visibleIndex.entriesSnapshot() {
            previousSiblingMarkerByDepth = previousSiblingMarkerByDepth.filter {
                $0.key <= visible.depth
            }

            let markerKind = Self.markerKind(
                for: document.block(visible.blockID)?.kind,
                previousSiblingMarker: previousSiblingMarkerByDepth[visible.depth]
            )
            if markerKind != .none {
                markerKindByBlockID[visible.blockID] = markerKind
            }
            if case .orderedListItem = markerKind {
                containsOrderedMarkers = true
            }
            previousSiblingMarkerByDepth[visible.depth] = markerKind
        }
    }

    func markerKind(for blockID: BlockID) -> BlockMarkerKind {
        markerKindByBlockID[blockID] ?? .none
    }
}

// MARK: - Marker Kind Projection

extension BlockMarkerSequence {
    static func markerKind(
        for blockKind: BlockKind?,
        previousSiblingMarker: BlockMarkerKind?
    ) -> BlockMarkerKind {
        guard let blockKind else { return .none }

        switch blockKind {
        case .unorderedListItem:
            return .unorderedListItem
        case .orderedListItem(let restartNumber):
            if let restartNumber {
                return .orderedListItem(number: max(1, restartNumber))
            }
            if case .orderedListItem(let previousNumber) = previousSiblingMarker {
                return .orderedListItem(number: previousNumber + 1)
            }
            return .orderedListItem(number: 1)
        case .todo(let isChecked):
            return .todo(isChecked: isChecked)
        case .paragraph, .heading, .quote, .codeBlock, .divider:
            return .none
        }
    }

    static func isOrderedList(_ blockKind: BlockKind?) -> Bool {
        if case .orderedListItem = blockKind {
            return true
        }
        return false
    }
}
