import SlopadEditorCoreModel

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
            guard let resolvedSpan = resolveTextSpan(textSelection) else { throw .abort }
            if !textSelection.isSingleBlock {
                try replaceCrossBlockText(
                    in: resolvedSpan,
                    with: text,
                    operations: &operations,
                    changed: &changed
                )
                return
            }
            guard let range = textSelection.rangeInSingleBlock else { throw .abort }
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

    /// Replaces a normalized cross-block text span while preserving the earlier endpoint
    /// block as the canonical survivor.
    ///
    /// Descendants after the later endpoint are outside the text range. Before removing the
    /// selected structural frontier, they are promoted past every removed ancestor to the
    /// nearest surviving parent at the removed frontier's position.
    private func replaceCrossBlockText(
        in span: ResolvedTextSpan,
        with replacementText: String,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard
            span.blockIDs.count >= 2,
            let startBlock = state.document.block(span.start.blockID),
            let endBlock = state.document.block(span.end.blockID)
        else {
            throw .abort
        }

        let armedMarks = state.storedMarks
        let shouldCaptureInputCandidate = inputRuleRunner.mayMatch(committedText: replacementText)
            || replacementText == "/"
        var mergedContent = startBlock.content
        mergedContent.delete(TextRange(span.start.offset, startBlock.content.length))
        appendSuffix(
            of: endBlock.content,
            from: span.end.offset,
            to: &mergedContent
        )
        let inputRuleCandidate = mergedContent.insert(
            replacementText,
            at: span.start.offset,
            capturingInputRuleCandidateWithMaximumLookback: shouldCaptureInputCandidate
                ? max(
                    inputRuleRunner.maximumCandidateLookback,
                    SlashCommandInputRule.maximumCandidateLookback
                ) : nil
        )
        Self.applyStoredMarks(
            armedMarks,
            to: &mergedContent,
            over: span.start.offset,
            length: replacementText.count
        )
        try requireDocumentMutationSuccess(
            state.document.replaceContent(blockID: span.start.blockID, content: mergedContent)
        )
        changed.insert(span.start.blockID)

        let removedSet = Set(span.blockIDs.dropFirst())
        try promoteUnselectedDescendants(
            outside: removedSet,
            operations: &operations,
            changed: &changed
        )

        let removalRoots = state.document.topLevelBlockIDs(Array(removedSet))
        var removedBlockIDs: [BlockID] = []
        for blockID in removalRoots {
            switch state.document.removeSubtree(blockID) {
            case .success(let removed):
                removedBlockIDs.append(contentsOf: removed)
            case .failure:
                throw .abort
            }
        }
        guard removedSet.isSubset(of: Set(removedBlockIDs)) else { throw .abort }
        changed.formUnion(removedBlockIDs)
        operations.append(.deleteBlocks(blockIDs: removedBlockIDs))

        state.selection = .caret(
            blockID: span.start.blockID,
            offset: span.start.offset + replacementText.count
        )
        if !replacementText.isEmpty {
            try applyInputRulesIfNeeded(
                committedText: replacementText,
                blockID: span.start.blockID,
                candidate: inputRuleCandidate,
                operations: &operations,
                changed: &changed
            )
        }
    }

    private func appendSuffix(
        of content: BlockContent,
        from offset: Int,
        to destination: inout BlockContent
    ) {
        let suffixRange = TextRange(offset, content.length)
        guard !suffixRange.isEmpty else { return }
        let insertionOffset = destination.length
        destination.insert(content.text.substring(in: suffixRange), at: insertionOffset)
        for mark in content.marks {
            let lower = max(mark.range.lowerBound, offset)
            let upper = min(mark.range.upperBound, content.length)
            guard upper > lower else { continue }
            destination.addMark(
                kind: mark.kind,
                range: TextRange(
                    insertionOffset + lower - offset,
                    insertionOffset + upper - offset
                )
            )
        }
    }

    private func promoteUnselectedDescendants(
        outside removedSet: Set<BlockID>,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        let frontier = removedSet.flatMap { removedID in
            state.document.children(of: removedID).filter { !removedSet.contains($0) }
        }
        guard !frontier.isEmpty else { return }

        let grouped = Dictionary(grouping: frontier) { childID -> BlockID? in
            var currentID = state.document.parentID(of: childID)
            while let blockID = currentID, removedSet.contains(blockID) {
                currentID = state.document.parentID(of: blockID)
            }
            return currentID
        }

        for (targetParentID, childIDs) in grouped {
            let orderedChildren = childIDs.sorted {
                (state.document.blockOrderPath(for: $0) ?? [])
                    .lexicographicallyPrecedes(state.document.blockOrderPath(for: $1) ?? [])
            }
            guard let firstChildID = orderedChildren.first else { continue }
            var removedAncestorID = state.document.parentID(of: firstChildID)
            var highestRemovedAncestorID: BlockID?
            while let blockID = removedAncestorID, removedSet.contains(blockID) {
                highestRemovedAncestorID = blockID
                removedAncestorID = state.document.parentID(of: blockID)
            }
            let targetSiblings = state.document.children(of: targetParentID)
            let insertionIndex = highestRemovedAncestorID
                .flatMap { targetSiblings.firstIndex(of: $0) }
                .map { $0 + 1 }
                ?? targetSiblings.count
            switch state.document.moveSubtreeRange(
                orderedChildren,
                toParentID: targetParentID,
                index: insertionIndex
            ) {
            case .success:
                changed.formUnion(orderedChildren)
                operations.append(.moveBlocks(blockIDs: orderedChildren))
            case .failure:
                throw .abort
            }
        }
    }

}
