import SlopadCoreModel

// MARK: - Resolved Text Span

/// A command-time projection of one canonical text selection.
///
/// The selection keeps its original direction. `start` and `end` are normalized only for
/// mutation and projection, and `blockIDs` contains exactly the canonical DFS span rather
/// than a flattened document coordinate or a whole-document order array.
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
            selection.focus.offset <= focusBlock.content.length,
            let anchorPath = document.blockOrderPath(for: selection.anchor.blockID),
            let focusPath = document.blockOrderPath(for: selection.focus.blockID)
        else {
            return nil
        }

        let anchorComesFirst =
            anchorPath == focusPath
            ? selection.anchor.offset <= selection.focus.offset
            : anchorPath.lexicographicallyPrecedes(focusPath)
        let start = anchorComesFirst ? selection.anchor : selection.focus
        let end = anchorComesFirst ? selection.focus : selection.anchor

        guard let blockIDs = document.depthFirstBlockIDs(from: start.blockID, through: end.blockID)
        else {
            return nil
        }
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
}
