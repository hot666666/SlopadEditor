import SlopadCoreModel

// MARK: - EditorModel InputRules

extension EditorModel {
    /// Static because there is one rule set today. When rules become format-supplied per
    /// document this has to become instance state — see #31.
    static let inputRuleRunner = EditorInputRuleRunner(rules: MarkdownBlockInputRules.all)

    /// Applies whatever the text just committed completed, if anything.
    ///
    /// Throws on a failed mutation instead of returning, so a rule that gets halfway cannot
    /// leave the marker deleted and the block kind unchanged. The caller is already inside
    /// `apply`, which rolls the whole transaction back on `EditorCommandAbort` — the previous
    /// implementation returned `false` on failure and kept the partial edit.
    func applyInputRulesIfNeeded(
        committedText: String,
        blockID: BlockID,
        caretOffset: Int,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard let block = document.block(blockID), block.kind.acceptsInputRules else { return }
        guard
            let effect = Self.inputRuleRunner.effect(
                committedText: committedText,
                in: block.content.text,
                caretOffset: caretOffset
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
