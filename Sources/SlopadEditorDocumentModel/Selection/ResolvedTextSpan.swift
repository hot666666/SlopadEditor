import SlopadEditorCoreModel

// MARK: - Resolved Text Span

/// A command-time projection of one canonical text selection.
///
/// The selection keeps its original direction. `start` and `end` are normalized only for
/// mutation and projection, and `blockIDs` contains exactly the canonical DFS span rather
/// than introducing a flattened document coordinate into canonical state.
package struct ResolvedTextSpan: Sendable {
    package let selection: TextSelection
    package let start: TextPosition
    package let end: TextPosition
    package let blockIDs: [BlockID]
    package let fragments: [ResolvedTextFragment]
}

package struct ResolvedTextFragment: Sendable {
    package let blockID: BlockID
    package let range: TextRange

    package init(blockID: BlockID, range: TextRange) {
        self.blockID = blockID
        self.range = range
    }
}

extension EditorModel {
    package func resolveTextSpan(_ selection: TextSelection) -> ResolvedTextSpan? {
        guard
            let anchorBlock = document.block(selection.anchor.blockID),
            let focusBlock = document.block(selection.focus.blockID),
            selection.anchor.offset >= 0,
            selection.anchor.offset <= anchorBlock.content.length,
            selection.focus.offset >= 0,
            selection.focus.offset <= focusBlock.content.length
        else {
            return nil
        }

        let order = canonicalBlockOrder()
        guard
            let anchorRank = order.rankByBlockID[selection.anchor.blockID],
            let focusRank = order.rankByBlockID[selection.focus.blockID]
        else { return nil }

        let anchorComesFirst =
            anchorRank == focusRank
            ? selection.anchor.offset <= selection.focus.offset
            : anchorRank < focusRank
        let start = anchorComesFirst ? selection.anchor : selection.focus
        let end = anchorComesFirst ? selection.focus : selection.anchor

        guard
            let startRank = order.rankByBlockID[start.blockID],
            let endRank = order.rankByBlockID[end.blockID],
            startRank <= endRank
        else { return nil }
        let blockIDs = Array(order.blockIDs[startRank...endRank])
        let fragments = blockIDs.compactMap { blockID -> ResolvedTextFragment? in
            guard let block = document.block(blockID) else { return nil }
            let range: TextRange
            if start.blockID == end.blockID {
                range = TextRange(start.offset, end.offset)
            } else if blockID == start.blockID {
                range = TextRange(start.offset, block.content.length)
            } else if blockID == end.blockID {
                range = TextRange(0, end.offset)
            } else {
                range = TextRange(0, block.content.length)
            }
            return ResolvedTextFragment(blockID: blockID, range: range)
        }
        guard fragments.count == blockIDs.count else { return nil }
        return ResolvedTextSpan(
            selection: selection,
            start: start,
            end: end,
            blockIDs: blockIDs,
            fragments: fragments
        )
    }

    private func canonicalBlockOrder() -> CanonicalBlockOrder {
        if let cachedCanonicalBlockOrder,
            cachedCanonicalBlockOrder.canonicalStructureRevision == canonicalStructureRevision
        {
            return cachedCanonicalBlockOrder
        }
        let blockIDs = document.editorBlockInputs.map(\.id)
        let order = CanonicalBlockOrder(
            canonicalStructureRevision: canonicalStructureRevision,
            blockIDs: blockIDs,
            rankByBlockID: Dictionary(
                uniqueKeysWithValues: blockIDs.enumerated().map { ($0.element, $0.offset) }
            )
        )
        cachedCanonicalBlockOrder = order
        canonicalBlockOrderRebuildCount += 1
        return order
    }
}

// MARK: - Canonical Block Order

struct CanonicalBlockOrder {
    let canonicalStructureRevision: UInt64
    let blockIDs: [BlockID]
    let rankByBlockID: [BlockID: Int]
}
