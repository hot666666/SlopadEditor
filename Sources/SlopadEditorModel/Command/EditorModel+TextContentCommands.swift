import SlopadCoreModel

// MARK: - Text Content Commands

extension EditorModel {
    /// Marks freshly inserted text with whatever the caret had armed.
    fileprivate static func applyStoredMarks(
        _ marks: Set<BlockContent.InlineMark.Kind>,
        to content: inout BlockContent,
        over offset: Int,
        length: Int
    ) {
        guard !marks.isEmpty, length > 0 else { return }
        let range = TextRange(offset, offset + length)
        for kind in marks.sorted() {
            content.addMark(kind: kind, range: range)
        }
    }

    func insertText(
        _ text: String,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        switch selection {
        case .inactive:
            throw .abort

        case .caret(let position):
            let blockID = position.blockID
            guard state.document.containsBlock(blockID) else { throw .abort }
            let offset = position.offset
            let armedMarks = state.storedMarks
            let shouldCaptureInputCandidate = inputRuleRunner.mayMatch(committedText: text)
                || text == "/"
            var inputRuleCandidate: EditorInputRuleCandidate?
            try requireDocumentMutationSuccess(
                state.document.updateContent(blockID: blockID) { content in
                    inputRuleCandidate = content.insert(
                        text,
                        at: offset,
                        capturingInputRuleCandidateWithMaximumLookback: shouldCaptureInputCandidate
                            ? max(
                                inputRuleRunner.maximumCandidateLookback,
                                SlashCommandInputRule.maximumCandidateLookback
                            ) : nil
                    )
                    Self.applyStoredMarks(armedMarks, to: &content, over: offset, length: text.count)
                })
            let newOffset = offset + text.count
            // Assigned rather than replaced: the caret moved because a character was typed,
            // so anything armed for this spot still applies to the next one.
            state.selection = .caret(blockID: blockID, offset: newOffset)
            changed.insert(blockID)
            try applyInputRulesIfNeeded(
                committedText: text, blockID: blockID, candidate: inputRuleCandidate,
                operations: &operations, changed: &changed)

        case .text(let textSelection):
            guard textSelection.isSingleBlock, let range = textSelection.rangeInSingleBlock else {
                throw .abort
            }
            let blockID = textSelection.anchor.blockID
            guard state.document.containsBlock(blockID) else { throw .abort }
            let armedMarks = state.storedMarks
            let shouldCaptureInputCandidate = inputRuleRunner.mayMatch(committedText: text)
                || text == "/"
            var inputRuleCandidate: EditorInputRuleCandidate?
            try requireDocumentMutationSuccess(
                state.document.updateContent(blockID: blockID) { content in
                    content.delete(range)
                    inputRuleCandidate = content.insert(
                        text,
                        at: range.lowerBound,
                        capturingInputRuleCandidateWithMaximumLookback: shouldCaptureInputCandidate
                            ? max(
                                inputRuleRunner.maximumCandidateLookback,
                                SlashCommandInputRule.maximumCandidateLookback
                            ) : nil
                    )
                    Self.applyStoredMarks(
                        armedMarks, to: &content, over: range.lowerBound, length: text.count)
            })
            state.selection = .caret(blockID: blockID, offset: range.lowerBound + text.count)
            changed.insert(blockID)
            try applyInputRulesIfNeeded(
                committedText: text, blockID: blockID, candidate: inputRuleCandidate,
                operations: &operations, changed: &changed)

        case .blocks:
            throw .abort
        }
    }

    func replaceText(
        blockID: BlockID,
        range: TextRange,
        text: String,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard !range.isEmpty || !text.isEmpty else { throw .abort }
        guard state.document.containsBlock(blockID) else { throw .abort }
        // This — not `insertText` — is what an ordinary keystroke and an IME commit arrive
        // as, so stored marks have to be honored here or arming a style would only work for
        // programmatic insertions. A multi-character replacement is evaluated once using its
        // final character because IME commits need that behavior. Paste is separately routed
        // through `insertText`, where the pasted string is likewise evaluated once.
        let armedMarks = state.storedMarks
        let shouldCaptureInputCandidate = inputRuleRunner.mayMatch(committedText: text)
            || text == "/"
        var inputRuleCandidate: EditorInputRuleCandidate?
        try requireDocumentMutationSuccess(
            state.document.updateContent(blockID: blockID) { content in
                content.delete(range)
                inputRuleCandidate = content.insert(
                    text,
                    at: range.lowerBound,
                    capturingInputRuleCandidateWithMaximumLookback: shouldCaptureInputCandidate
                        ? max(
                            inputRuleRunner.maximumCandidateLookback,
                            SlashCommandInputRule.maximumCandidateLookback
                        ) : nil
                )
                Self.applyStoredMarks(
                    armedMarks, to: &content, over: range.lowerBound, length: text.count)
            })
        let newOffset = range.lowerBound + text.count
        state.selection = .caret(blockID: blockID, offset: newOffset)
        changed.insert(blockID)
        if !text.isEmpty {
            try applyInputRulesIfNeeded(
                committedText: text, blockID: blockID, candidate: inputRuleCandidate,
                operations: &operations, changed: &changed)
        }
    }

    func deleteText(
        blockID: BlockID,
        range: TextRange,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard state.document.containsBlock(blockID) else { throw .abort }
        try requireDocumentMutationSuccess(
            state.document.updateContent(blockID: blockID) { content in
                content.delete(range)
            })
        state.selection = .caret(blockID: blockID, offset: range.lowerBound)
        changed.insert(blockID)
    }

}
