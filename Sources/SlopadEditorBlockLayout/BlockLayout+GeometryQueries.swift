import SlopadCoreModel

// MARK: - Geometry Queries

extension BlockLayout {
    package var totalHeight: Double {
        heightIndex.totalHeight
    }

    private var lastBlockID: BlockID? {
        guard heightIndex.count > 0 else { return nil }
        return heightIndex.entry(at: heightIndex.count - 1)?.blockID
    }

    package func blockID(atY yOffset: Double) -> BlockID? {
        heightIndex.blockID(atY: yOffset)
    }

    private func blockIDForDropTarget(atY yOffset: Double) -> BlockID? {
        if let blockID = blockID(atY: max(yOffset, 0)) {
            return blockID
        }
        guard yOffset >= totalHeight else { return nil }
        return lastBlockID
    }

    package func blockDropTarget(
        atY yOffset: Double,
        viewportWidth: Double
    ) -> (target: BlockDropTarget, indicator: EditorRect)? {
        guard
            let targetBlockID = blockIDForDropTarget(atY: yOffset),
            let geometry = blockGeometry(for: targetBlockID)
        else {
            return nil
        }

        let placement: BlockDropTarget.Placement =
            yOffset < geometry.topY + geometry.height / 2 ? .before : .after
        let indicatorY: Double
        switch placement {
        case .before:
            indicatorY = geometry.topY
        case .after:
            indicatorY = geometry.topY + geometry.height
        }
        return (
            BlockDropTarget(blockID: targetBlockID, placement: placement),
            EditorRect(x: 0, y: indicatorY - 1, width: viewportWidth, height: 2)
        )
    }

    package func blockGeometry(
        for blockID: BlockID
    ) -> BlockLayoutGeometry? {
        guard let index = heightIndex.index(of: blockID) else { return nil }
        return blockGeometry(at: index)
    }

    /// Canonical visible-order rank from the prepared height index.
    /// Session uses this to compare selection endpoints without walking sibling arrays.
    package func visibleOrderIndex(of blockID: BlockID) -> Int? {
        heightIndex.index(of: blockID)
    }

    private func blockGeometry(
        at index: Int
    ) -> BlockLayoutGeometry? {
        guard
            let entry = heightIndex.entry(at: index),
            let topY = heightIndex.topY(for: entry.blockID),
            measurementsByBlockID[entry.blockID] != nil,
            let visible = visibleIndex?.entry(for: entry.blockID),
            let markerSequence
        else {
            return nil
        }
        return BlockLayoutGeometry(
            blockID: entry.blockID,
            topY: topY,
            height: entry.height,
            depth: visible.depth,
            markerKind: markerSequence.markerKind(for: entry.blockID)
        )
    }

    package func visibleGeometries(
        yOffset: Double,
        viewportHeight: Double
    ) -> [BlockLayoutGeometry] {
        let range = heightIndex.visibleRange(
            yOffset: yOffset,
            viewportHeight: viewportHeight
        )
        var geometries: [BlockLayoutGeometry] = []
        geometries.reserveCapacity(range.count)
        for index in range {
            if let geometry = blockGeometry(at: index) {
                geometries.append(geometry)
            }
        }
        return geometries
    }
}
