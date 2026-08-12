import SlopadCoreModel

// MARK: - BlockMarkerSequence Reuse

extension BlockMarkerSequence {
    func canReuseWithoutMarkerRefresh(
        after changeSet: BlockLayoutChangeSet,
        document: Document
    ) -> Bool {
        guard markerKindByBlockID.isEmpty else { return false }

        let markerRelevantBlockIDs = Set(changeSet.insertedBlockIDs).union(
            changeSet.updatedBlockIDs)
        return markerRelevantBlockIDs.allSatisfy { blockID in
            Self.markerKind(
                for: document.block(blockID)?.kind,
                previousSiblingMarker: nil
            ) == .none
        }
    }

    mutating func applyIndependentStructuralMutation(
        document: Document,
        visibleIndex: VisibleBlockIndex,
        changeSet: BlockLayoutChangeSet
    ) -> Bool {
        guard !containsOrderedMarkers else { return false }

        let removed = Set(changeSet.removedBlockIDs)
        let moved = Set(changeSet.movedBlockIDs)
        let inserted = Set(changeSet.insertedBlockIDs)
        let relocating = removed.union(moved).union(inserted)
        let placedBlockIDs = moved.union(inserted)
        guard
            placedBlockIDs.allSatisfy({
                !Self.isOrderedList(document.block($0)?.kind)
            })
        else {
            return false
        }
        for blockID in removed {
            markerKindByBlockID.removeValue(forKey: blockID)
        }

        for blockID in placedBlockIDs where visibleIndex.entry(for: blockID) != nil {
            setIndependentMarkerKind(for: blockID, document: document)
        }

        let updatedOnly = changeSet.updatedBlockIDs.subtracting(relocating)
        guard
            updatedOnly.allSatisfy({
                !Self.isOrderedList(document.block($0)?.kind)
            })
        else {
            return false
        }
        for blockID in updatedOnly where visibleIndex.entry(for: blockID) != nil {
            setIndependentMarkerKind(for: blockID, document: document)
        }
        return true
    }

    mutating func refreshIndependentMarkers(
        blockIDs: Set<BlockID>,
        document: Document,
        visibleIndex: VisibleBlockIndex
    ) -> Bool {
        guard !containsOrderedMarkers else { return false }

        for blockID in blockIDs {
            guard visibleIndex.entry(for: blockID) != nil else { continue }
            let kind = document.block(blockID)?.kind
            guard !Self.isOrderedList(kind) else { return false }
            setIndependentMarkerKind(for: blockID, document: document)
        }
        return true
    }

    private mutating func setIndependentMarkerKind(for blockID: BlockID, document: Document) {
        let kind = document.block(blockID)?.kind
        guard !Self.isOrderedList(kind) else { return }
        let markerKind = Self.markerKind(for: kind, previousSiblingMarker: nil)
        guard markerKind != .none else {
            markerKindByBlockID.removeValue(forKey: blockID)
            return
        }
        markerKindByBlockID[blockID] = markerKind
    }
}
