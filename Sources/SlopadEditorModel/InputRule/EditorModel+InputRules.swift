import SlopadCoreModel

// MARK: - EditorModel InputRules

extension EditorModel {
    /// Applies whatever the text just committed completed, if anything.
    ///
    /// Throws on a failed mutation instead of returning, so a rule that gets halfway cannot
    /// leave the marker deleted and the block kind unchanged. The caller is already inside
    /// `apply`, which rolls the whole transaction back on `EditorCommandAbort` — the previous
    /// implementation returned `false` on failure and kept the partial edit.
    func applyInputRulesIfNeeded(
        committedText: String,
        blockID: BlockID,
        candidate: EditorInputRuleCandidate?,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard let block = document.block(blockID), block.kind.acceptsInputRules,
            let candidate
        else { return }
        guard
            let effect = inputRuleRunner.effect(
                committedText: committedText,
                candidate: candidate
            )
        else { return }

        switch effect {
        case .convertBlock(let removing, let kind):
            try requireDocumentMutationSuccess(
                state.document.updateContent(blockID: blockID) { content in
                    content.delete(removing)
                })
            try requireDocumentMutationSuccess(
                state.document.setBlockKind(blockID: blockID, kind: kind))
            // The marker is gone and the block is a different kind now. That is a
            // relocation, not a caret advancing through typing, so anything armed for the
            // old text does not carry over.
            state.replaceSelection(.caret(blockID: blockID, offset: 0))
            operations.append(.refreshMarker)
            changed.insert(blockID)

        case .applyInline(let marks, let removals, let marked):
            guard isValidInlineEffect(removals: removals, marked: marked, in: block.content) else {
                throw .abort
            }
            let mappedMarkRange = mapRangeAfterRemoving(marked, removals: removals)
            try requireDocumentMutationSuccess(
                state.document.updateContent(blockID: blockID) { content in
                    for removal in removals.sorted(by: { $0.lowerBound > $1.lowerBound }) {
                        content.delete(removal)
                    }
                    for mark in marks.sorted() {
                        content.addMark(kind: mark, range: mappedMarkRange)
                    }
                })
            // This remains part of the same text edit, rather than a deliberate cursor
            // relocation: any stored style the user armed must continue through the
            // converted inline span.
            state.selection = .caret(blockID: blockID, offset: mappedMarkRange.upperBound)
            changed.insert(blockID)

        }
    }

    private func isValidInlineEffect(
        removals: [TextRange],
        marked: TextRange,
        in content: BlockContent
    ) -> Bool {
        guard !removals.isEmpty, !marked.isEmpty, marked.upperBound <= content.length else {
            return false
        }
        let sorted = removals.sorted { $0.lowerBound < $1.lowerBound }
        guard sorted.allSatisfy({ !$0.isEmpty && $0.upperBound <= content.length }) else { return false }
        guard zip(sorted, sorted.dropFirst()).allSatisfy({ $0.upperBound <= $1.lowerBound }) else {
            return false
        }
        return sorted.allSatisfy { !$0.intersects(marked) }
    }

    private func mapRangeAfterRemoving(_ range: TextRange, removals: [TextRange]) -> TextRange {
        TextRange(
            mapOffsetAfterRemoving(range.lowerBound, removals: removals),
            mapOffsetAfterRemoving(range.upperBound, removals: removals)
        )
    }

    private func mapOffsetAfterRemoving(_ offset: Int, removals: [TextRange]) -> Int {
        offset - removals.reduce(into: 0) { removed, range in
            if range.upperBound <= offset { removed += range.length }
        }
    }
}

// MARK: - Eligibility

extension BlockKind {
    /// Code blocks take their text literally; recognizing syntax inside one would convert
    /// the very thing the user is trying to show.
    fileprivate var acceptsInputRules: Bool {
        if case .codeBlock = self { return false }
        return true
    }
}
