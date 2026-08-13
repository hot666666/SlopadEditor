import SlopadEditorCoreModel

// MARK: - Resolved Command Targets

/// The canonical command-time interpretation of one exact selection.
///
/// Session asks the model for this value both when projecting stable command facts and
/// immediately before applying a command. Text and structural targets deliberately differ
/// for block selection: inline formatting walks non-empty text-capable descendants, while
/// block-kind and structural commands act on selected top-level roots only.
package struct ResolvedCommandTargets: Sendable {
    package enum InlineTarget: Sendable {
        case caret(TextPosition)
        case fragments([ResolvedTextFragment])
    }

    package let selection: EditorSelection
    package let inlineTarget: InlineTarget?
    /// The complete logical block span touched by T1/TN, or selected top-level roots for B.
    package let blockFactIDs: [BlockID]
    /// Exact roots used by block-kind, indent, and outdent commands.
    package let structuralBlockIDs: [BlockID]
}

extension EditorModel {
    package func resolveCommandTargets() -> ResolvedCommandTargets? {
        resolveCommandTargets(for: selection)
    }

    package func resolveCommandTargets(
        for selection: EditorSelection
    ) -> ResolvedCommandTargets? {
        switch selection {
        case .inactive:
            return nil

        case .caret(let position):
            guard
                let block = document.block(position.blockID),
                position.offset >= 0,
                position.offset <= block.content.length
            else { return nil }
            return ResolvedCommandTargets(
                selection: selection,
                inlineTarget: block.kind.isTextCapable ? .caret(position) : nil,
                blockFactIDs: [position.blockID],
                structuralBlockIDs: [position.blockID]
            )

        case .text(let textSelection):
            guard let span = resolveTextSpan(textSelection) else { return nil }
            let fragments = span.fragments.filter { fragment in
                guard let block = document.block(fragment.blockID) else { return false }
                return block.kind.isTextCapable && !fragment.range.isEmpty
            }
            let inlineTarget: ResolvedCommandTargets.InlineTarget?
            if textSelection.isSingleBlock, span.fragments.first?.range.isEmpty == true,
                let block = document.block(textSelection.focus.blockID),
                block.kind.isTextCapable
            {
                inlineTarget = .caret(textSelection.focus)
            } else {
                inlineTarget = fragments.isEmpty ? nil : .fragments(fragments)
            }
            return ResolvedCommandTargets(
                selection: selection,
                inlineTarget: inlineTarget,
                blockFactIDs: span.blockIDs,
                structuralBlockIDs: span.blockIDs
            )

        case .blocks(let blockSelection):
            guard blockSelection.blockIDs.allSatisfy(document.containsBlock) else { return nil }
            let roots = topLevelBlocksPreservingSelectionOrder(blockSelection.blockIDs)
            guard !roots.isEmpty else { return nil }
            let fragments = fullTextFragments(inSubtreesRootedAt: roots)
            return ResolvedCommandTargets(
                selection: selection,
                inlineTarget: fragments.isEmpty ? nil : .fragments(fragments),
                blockFactIDs: roots,
                structuralBlockIDs: roots
            )
        }
    }

    package func canIndentBlocks(_ blockIDs: [BlockID]) -> Bool {
        let moving = topLevelBlocksPreservingSelectionOrder(blockIDs)
        guard let first = moving.first else { return false }
        let siblings = document.children(of: document.parentID(of: first))
        guard let index = siblings.firstIndex(of: first), index > 0 else { return false }
        let newParentID = siblings[index - 1]
        return !moving.contains(newParentID)
            && document.containsBlock(newParentID)
            && document.parentID(of: first) != newParentID
    }

    package func canOutdentBlocks(_ blockIDs: [BlockID]) -> Bool {
        topLevelBlocksPreservingSelectionOrder(blockIDs).contains {
            document.parentID(of: $0) != nil
        }
    }

    package func canSetBlockKind(_ kind: BlockKind, blockIDs: [BlockID]) -> Bool {
        !blockIDs.isEmpty && blockIDs.allSatisfy { document.block($0) != nil }
            && blockIDs.contains { document.block($0)?.kind != kind }
    }

    private func fullTextFragments(inSubtreesRootedAt roots: [BlockID])
        -> [ResolvedTextFragment]
    {
        var fragments: [ResolvedTextFragment] = []
        var stack = Array(roots.reversed())
        while let blockID = stack.popLast() {
            guard let block = document.block(blockID) else { continue }
            if block.kind.isTextCapable, block.content.length > 0 {
                fragments.append(
                    ResolvedTextFragment(
                        blockID: blockID,
                        range: TextRange(0, block.content.length)
                    )
                )
            }
            stack.append(contentsOf: document.children(of: blockID).reversed())
        }
        return fragments
    }

    /// Command targets produced by Session are already in canonical selection order.
    /// Filtering ancestors is O(K * depth) and avoids rebuilding order paths whose sibling
    /// scans make a flat 10,000-block selection quadratic.
    private func topLevelBlocksPreservingSelectionOrder(
        _ blockIDs: [BlockID]
    ) -> [BlockID] {
        let selected = Set(blockIDs)
        return blockIDs.filter { !document.hasAncestor(in: selected, of: $0) }
    }
}
