import SlopadEditorBlockLayout
import SlopadCoreModel

// MARK: - Render Damage

extension EditorSession {
    public func redrawRects(
        for update: EditorUpdate,
        in viewport: EditorViewport
    ) -> [EditorRect] {
        let visibleRect = viewport.visibleRect
        guard isRenderable(visibleRect) else { return [] }

        guard blockLayout.hasPreparedLayout(for: viewport) else {
            _ = preparedLayout(for: viewport)
            return [visibleRect]
        }
        guard !requiresFullRedrawFallback(update) else {
            _ = preparedLayout(for: viewport)
            return [visibleRect]
        }

        let selectionChanged = update.previousSelection != update.selection
        let oldVisibleBlockIDs = visibleBlockIDs(in: viewport)
        var affectedBlockIDs = update.invalidation.blockIDs
        if selectionChanged {
            affectedBlockIDs.formUnion(
                visibleSelectionBlockIDs(update.previousSelection, among: oldVisibleBlockIDs)
            )
            affectedBlockIDs.formUnion(
                visibleSelectionBlockIDs(update.selection, among: oldVisibleBlockIDs)
            )
        }
        guard !affectedBlockIDs.isEmpty else {
            _ = preparedLayout(for: viewport)
            return []
        }

        let oldFrames = layoutFrames(
            for: affectedBlockIDs,
            blockLayout: blockLayout,
            viewportWidth: viewport.width
        )
        _ = preparedLayout(for: viewport)
        if selectionChanged {
            let newVisibleBlockIDs = visibleBlockIDs(in: viewport)
            affectedBlockIDs.formUnion(
                visibleSelectionBlockIDs(update.previousSelection, among: newVisibleBlockIDs)
            )
            affectedBlockIDs.formUnion(
                visibleSelectionBlockIDs(update.selection, among: newVisibleBlockIDs)
            )
        }
        let newFrames = layoutFrames(
            for: affectedBlockIDs,
            blockLayout: blockLayout,
            viewportWidth: viewport.width
        )

        guard !oldFrames.isEmpty || !newFrames.isEmpty else { return [] }

        if requiresTailRedraw(
            update: update,
            oldFrames: oldFrames,
            newFrames: newFrames
        ) {
            let frames = Array(oldFrames.values) + Array(newFrames.values)
            guard let minY = frames.map(\.minY).min() else {
                return []
            }
            let tail = EditorRect(
                x: visibleRect.x,
                y: minY,
                width: visibleRect.width,
                height: visibleRect.maxY - minY
            )
            return clipped([tail], to: visibleRect)
        }

        return clipped(
            Array(oldFrames.values) + Array(newFrames.values),
            to: visibleRect
        )
    }
}

extension EditorSession {
    fileprivate func visibleBlockIDs(in viewport: EditorViewport) -> Set<BlockID> {
        Set(
            blockLayout.visibleGeometries(
                yOffset: viewport.scrollY,
                viewportHeight: viewport.height
            ).map(\.blockID)
        )
    }

    fileprivate func visibleSelectionBlockIDs(
        _ selection: EditorSelection?,
        among visibleBlockIDs: Set<BlockID>
    ) -> Set<BlockID> {
        guard let selection else { return [] }
        switch selection {
        case .inactive:
            return []
        case .caret(let position):
            return visibleBlockIDs.contains(position.blockID) ? [position.blockID] : []
        case .text(let textSelection):
            return visibleIDs(
                between: textSelection.anchor.blockID,
                and: textSelection.focus.blockID,
                among: visibleBlockIDs
            )
        case .blocks(let blockSelection):
            return visibleIDs(
                between: blockSelection.anchor,
                and: blockSelection.focus,
                among: visibleBlockIDs
            )
        }
    }

    fileprivate func visibleIDs(
        between firstID: BlockID,
        and secondID: BlockID,
        among visibleBlockIDs: Set<BlockID>
    ) -> Set<BlockID> {
        guard
            let firstIndex = blockLayout.visibleOrderIndex(of: firstID),
            let secondIndex = blockLayout.visibleOrderIndex(of: secondID)
        else {
            return []
        }
        let lowerBound = min(firstIndex, secondIndex)
        let upperBound = max(firstIndex, secondIndex)
        return Set(
            visibleBlockIDs.filter { blockID in
                guard let index = blockLayout.visibleOrderIndex(of: blockID) else { return false }
                return index >= lowerBound && index <= upperBound
            })
    }
}

// MARK: - Affected Blocks

// MARK: - Redraw Scope

private func requiresFullRedrawFallback(_ update: EditorUpdate) -> Bool {
    let invalidation = update.invalidation
    guard invalidation.layoutGeometryChanged || invalidation.visibleSequenceChanged else {
        return false
    }

    if invalidation.blockIDs.isEmpty {
        return true
    }

    return false
}

private func requiresTailRedraw(
    update: EditorUpdate,
    oldFrames: [BlockID: EditorRect],
    newFrames: [BlockID: EditorRect]
) -> Bool {
    let invalidation = update.invalidation
    if invalidation.visibleSequenceChanged {
        return true
    }

    let blockIDs = Set(oldFrames.keys).union(newFrames.keys)
    let hasGeometryChange = blockIDs.contains { blockID in
        guard let oldFrame = oldFrames[blockID], let newFrame = newFrames[blockID] else {
            return true
        }
        return !nearlyEqual(oldFrame.height, newFrame.height)
            || !nearlyEqual(oldFrame.y, newFrame.y)
    }
    return hasGeometryChange && !invalidation.blockIDs.isEmpty
}

// MARK: - Layout Frames

private func layoutFrames(
    for blockIDs: Set<BlockID>,
    blockLayout: BlockLayout,
    viewportWidth: Double
) -> [BlockID: EditorRect] {
    var frames: [BlockID: EditorRect] = [:]
    frames.reserveCapacity(blockIDs.count)
    for blockID in blockIDs {
        guard let geometry = blockLayout.blockGeometry(for: blockID) else { continue }
        frames[blockID] = geometry.frame(width: viewportWidth)
    }
    return frames
}

// MARK: - Rect Normalization

private func clipped(
    _ rects: [EditorRect],
    to visibleRect: EditorRect
) -> [EditorRect] {
    var output: [EditorRect] = []
    output.reserveCapacity(rects.count)
    for rect in rects {
        guard let clipped = rect.intersection(visibleRect), isRenderable(clipped) else {
            continue
        }
        if !output.contains(clipped) {
            output.append(clipped)
        }
    }
    return output.sorted {
        if nearlyEqual($0.minY, $1.minY) {
            return $0.minX < $1.minX
        }
        return $0.minY < $1.minY
    }
}

private func isRenderable(_ rect: EditorRect) -> Bool {
    !rect.isEmpty && rect.width > 0.01 && rect.height > 0.01
}

private func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) <= 0.01
}
