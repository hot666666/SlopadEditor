import SlopadCoreModel

// MARK: - Selection Queries

extension BlockLayout {
    package func blockSelection(
        from anchorBlockID: BlockID,
        to focusBlockID: BlockID,
        document: Document
    ) -> BlockSelection? {
        let visible = currentVisibleIndex(document: document)
        guard
            let anchorIndex = visible.index(of: anchorBlockID),
            let focusIndex = visible.index(of: focusBlockID)
        else {
            return nil
        }
        let range = min(anchorIndex, focusIndex)...max(anchorIndex, focusIndex)
        let blockIDs = visible.entries(in: range.lowerBound..<(range.upperBound + 1)).map(\.blockID)
        guard !blockIDs.isEmpty else { return nil }
        return BlockSelection(blockIDs: blockIDs, anchor: anchorBlockID, focus: focusBlockID)
    }

    package func allVisibleBlockSelection(document: Document) -> BlockSelection? {
        let visible = currentVisibleIndex(document: document)
        let blockIDs = visible.entries(in: 0..<visible.count).map(\.blockID)
        guard !blockIDs.isEmpty else { return nil }
        return BlockSelection(blockIDs: blockIDs)
    }

    package func blockSelection(
        intersectingYRange yRange: Range<Double>,
        document: Document
    ) -> BlockSelection? {
        guard yRange.lowerBound < yRange.upperBound else { return nil }
        let range = heightIndex.visibleRange(
            yOffset: yRange.lowerBound,
            viewportHeight: yRange.upperBound - yRange.lowerBound
        )
        guard !range.isEmpty else { return nil }

        let visible = currentVisibleIndex(document: document)
        let blockIDs = range.compactMap { index -> BlockID? in
            guard let blockID = heightIndex.entry(at: index)?.blockID,
                visible.entry(for: blockID) != nil
            else { return nil }
            return blockID
        }
        guard !blockIDs.isEmpty else { return nil }
        return BlockSelection(blockIDs: blockIDs)
    }

    package func movedBlockSelection(
        _ selection: BlockSelection,
        by offset: Int,
        document: Document
    ) -> BlockSelection? {
        let visible = currentVisibleIndex(document: document)
        let selectedIndexes = selection.blockIDs.compactMap {
            visible.index(of: $0)
        }.sorted()
        guard let first = selectedIndexes.first, let last = selectedIndexes.last else {
            return nil
        }

        let newFirst = first + offset
        let count = last - first + 1
        let newLast = newFirst + count - 1
        guard visible.entry(at: newFirst) != nil,
            visible.entry(at: newLast) != nil
        else {
            return nil
        }

        let anchorOffset = (visible.index(of: selection.anchor) ?? first) - first
        let focusOffset = (visible.index(of: selection.focus) ?? last) - first
        guard
            let anchor = visible.entry(at: newFirst + anchorOffset)?.blockID,
            let focus = visible.entry(at: newFirst + focusOffset)?.blockID
        else {
            return nil
        }

        let blockIDs = visible.entries(in: newFirst..<(newLast + 1)).map(\.blockID)
        guard !blockIDs.isEmpty else { return nil }
        return BlockSelection(blockIDs: blockIDs, anchor: anchor, focus: focus)
    }

    package func extendedBlockSelection(
        _ selection: BlockSelection,
        by offset: Int,
        document: Document
    ) -> BlockSelection? {
        let visible = currentVisibleIndex(document: document)
        guard
            let anchorIndex = visible.index(of: selection.anchor),
            let focusIndex = visible.index(of: selection.focus)
        else {
            return nil
        }

        let nextFocusIndex = focusIndex + offset
        guard visible.entry(at: nextFocusIndex) != nil else { return nil }

        let lower = min(anchorIndex, nextFocusIndex)
        let upper = max(anchorIndex, nextFocusIndex)
        let blockIDs = visible.entries(in: lower..<(upper + 1)).map(\.blockID)
        guard
            !blockIDs.isEmpty,
            let focus = visible.entry(at: nextFocusIndex)?.blockID
        else {
            return nil
        }
        return BlockSelection(blockIDs: blockIDs, anchor: selection.anchor, focus: focus)
    }
}
