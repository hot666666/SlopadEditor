import SlopadEditorCoreModel

// MARK: - Structured Paste Commands

extension EditorModel {
    func pasteStructured(
        _ payload: EditorClipboardPayload,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard payload.version == EditorClipboardPayload.currentVersion else { throw .abort }
        let sourceBlocks: [EditorBlockInput]
        switch payload.content {
        case .textSlice(let slice):
            sourceBlocks = slice.blocks
        case .blockSubtrees(let subtrees):
            sourceBlocks = subtrees.blocks
        }
        let forest = try validatedClipboardForest(sourceBlocks)

        switch selection {
        case .blocks(let blockSelection):
            try replaceBlockSelection(
                blockSelection,
                with: forest,
                operations: &operations,
                changed: &changed
            )
        case .caret, .text:
            if case .text = selection {
                try insertText("", operations: &operations, changed: &changed)
            }
            guard case .caret(let position) = selection else { throw .abort }
            if case .blockSubtrees = payload.content,
                try pasteCompleteForestAtBoundaryIfPossible(
                    forest,
                    position: position,
                    operations: &operations,
                    changed: &changed
                )
            {
                return
            }
            try pasteOpenEdgeForest(
                forest,
                position: position,
                operations: &operations,
                changed: &changed
            )
        case .inactive:
            throw .abort
        }
    }

    private func pasteCompleteForestAtBoundaryIfPossible(
        _ forest: ClipboardForest,
        position: TextPosition,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) -> Bool {
        guard let destination = state.document.block(position.blockID) else { throw .abort }
        guard position.offset == 0 || position.offset == destination.content.length else {
            return false
        }
        let parentID = destination.parentID
        guard
            let destinationIndex = state.document.children(of: parentID).firstIndex(
                of: destination.id)
        else { throw .abort }
        let insertionIndex = position.offset == 0 ? destinationIndex : destinationIndex + 1
        let insertedRoots = try insertFreshForest(
            forest,
            parentID: parentID,
            index: insertionIndex,
            changed: &changed
        )
        state.selection = .blocks(BlockSelection(blockIDs: insertedRoots))
        operations.append(.replaceDocument)
        return true
    }

    private func pasteOpenEdgeForest(
        _ forest: ClipboardForest,
        position: TextPosition,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard
            let destination = state.document.block(position.blockID),
            (0...destination.content.length).contains(position.offset),
            let firstRootID = forest.rootIDs.first,
            let lastRootID = forest.rootIDs.last,
            let first = forest.blocksByID[firstRootID],
            let last = forest.blocksByID[lastRootID]
        else { throw .abort }
        let prefix = contentSlice(destination.content, TextRange(0, position.offset))
        let suffix = contentSlice(
            destination.content,
            TextRange(position.offset, destination.content.length)
        )
        let originalChildren = state.document.children(of: destination.id)

        if forest.rootIDs.count == 1 {
            let merged = concatenateContents([prefix, first.content, suffix])
            try requireDocumentMutationSuccess(
                state.document.replaceContent(blockID: destination.id, content: merged)
            )
            if let descendantInputs = forest.inputsRemovingRoot(firstRootID) {
                let descendants = try validatedClipboardForest(descendantInputs)
                _ = try insertFreshForest(
                    descendants,
                    parentID: destination.id,
                    index: 0,
                    changed: &changed
                )
                operations.append(.replaceDocument)
            }
            state.selection = .caret(
                blockID: destination.id,
                offset: prefix.length + first.content.length
            )
            changed.insert(destination.id)
            return
        }

        let leading = concatenateContents([prefix, first.content])
        try requireDocumentMutationSuccess(
            state.document.replaceContent(blockID: destination.id, content: leading)
        )
        changed.insert(destination.id)

        if let firstDescendantInputs = forest.inputsRemovingRoot(firstRootID) {
            let firstDescendants = try validatedClipboardForest(firstDescendantInputs)
            _ = try insertFreshForest(
                firstDescendants,
                parentID: destination.id,
                index: 0,
                changed: &changed
            )
        }

        let parentID = destination.parentID
        guard
            let destinationIndex = state.document.children(of: parentID).firstIndex(
                of: destination.id)
        else { throw .abort }
        let middleRootIDs = Set(forest.rootIDs.dropFirst().dropLast())
        var nextRootIndex = destinationIndex + 1
        if !middleRootIDs.isEmpty {
            let middleForest = try validatedClipboardForest(
                forest.blocks.filter { input in
                    forest.rootByBlockID[input.id].map(middleRootIDs.contains) == true
                }
            )
            let roots = try insertFreshForest(
                middleForest,
                parentID: parentID,
                index: nextRootIndex,
                changed: &changed
            )
            nextRootIndex += roots.count
        }

        let trailingID = BlockID()
        let trailingContent = concatenateContents([last.content, suffix])
        try requireDocumentMutationSuccess(
            state.document.insertBlock(
                Block(id: trailingID, kind: destination.kind, content: trailingContent),
                parentID: parentID,
                index: nextRootIndex
            )
        )
        var lastDescendantRootCount = 0
        if let lastDescendantInputs = forest.inputsRemovingRoot(lastRootID) {
            let lastDescendants = try validatedClipboardForest(lastDescendantInputs)
            let roots = try insertFreshForest(
                lastDescendants,
                parentID: trailingID,
                index: 0,
                changed: &changed
            )
            lastDescendantRootCount = roots.count
        }
        if !originalChildren.isEmpty {
            try requireDocumentMutationSuccess(
                state.document.moveSubtreeRange(
                    originalChildren,
                    toParentID: trailingID,
                    index: lastDescendantRootCount
                )
            )
        }
        changed.insert(trailingID)
        changed.formUnion(originalChildren)
        state.selection = .caret(blockID: trailingID, offset: last.content.length)
        operations.append(.replaceDocument)
    }

    private func insertFreshForest(
        _ forest: ClipboardForest,
        parentID: BlockID?,
        index: Int,
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) -> [BlockID] {
        let remapped = Dictionary(uniqueKeysWithValues: forest.blocks.map { ($0.id, BlockID()) })
        var roots: [BlockID] = []
        var rootOffset = 0
        for input in forest.blocks {
            guard let newID = remapped[input.id] else { throw .abort }
            let newParentID = input.parentID.flatMap { remapped[$0] } ?? parentID
            let insertionIndex: Int?
            if input.parentID == nil {
                insertionIndex = index + rootOffset
                rootOffset += 1
                roots.append(newID)
            } else {
                insertionIndex = nil
            }
            try requireDocumentMutationSuccess(
                state.document.insertBlock(
                    Block(id: newID, kind: input.kind, content: input.content),
                    parentID: newParentID,
                    index: insertionIndex
                )
            )
        }
        changed.formUnion(remapped.values)
        return roots
    }

    private func contentSlice(_ content: BlockContent, _ range: TextRange) -> BlockContent {
        let range = range.clamped(to: content.length)
        let marks = content.marks.compactMap { mark -> BlockContent.InlineMark? in
            let lower = max(mark.range.lowerBound, range.lowerBound)
            let upper = min(mark.range.upperBound, range.upperBound)
            guard lower < upper else { return nil }
            return BlockContent.InlineMark(
                kind: mark.kind,
                range: TextRange(lower - range.lowerBound, upper - range.lowerBound)
            )
        }
        return BlockContent(text: content.text.substring(in: range), marks: marks)
    }

    private func concatenateContents(_ contents: [BlockContent]) -> BlockContent {
        var text = ""
        var marks: [BlockContent.InlineMark] = []
        for content in contents {
            let offset = text.count
            text += content.text
            marks.append(
                contentsOf: content.marks.map {
                    BlockContent.InlineMark(kind: $0.kind, range: $0.range.shifted(by: offset))
                })
        }
        return BlockContent(text: text, marks: marks)
    }

    private struct ClipboardForest {
        let blocks: [EditorBlockInput]
        let rootIDs: [BlockID]
        let blocksByID: [BlockID: EditorBlockInput]
        let rootByBlockID: [BlockID: BlockID]

        func inputsRemovingRoot(_ rootID: BlockID) -> [EditorBlockInput]? {
            let descendants = blocks.compactMap { input -> EditorBlockInput? in
                guard input.id != rootID, rootByBlockID[input.id] == rootID else { return nil }
                return EditorBlockInput(
                    id: input.id,
                    parentID: input.parentID == rootID ? nil : input.parentID,
                    kind: input.kind,
                    content: input.content
                )
            }
            return descendants.isEmpty ? nil : descendants
        }
    }

    private func validatedClipboardForest(
        _ blocks: [EditorBlockInput]
    ) throws(EditorCommandAbort) -> ClipboardForest {
        guard !blocks.isEmpty else { throw .abort }
        let ids = blocks.map(\.id)
        let idSet = Set(ids)
        guard idSet.count == ids.count else { throw .abort }
        var seen: Set<BlockID> = []
        var roots: [BlockID] = []
        var rootByBlockID: [BlockID: BlockID] = [:]
        for block in blocks {
            if let parentID = block.parentID {
                guard idSet.contains(parentID), seen.contains(parentID) else { throw .abort }
                guard let rootID = rootByBlockID[parentID] else { throw .abort }
                rootByBlockID[block.id] = rootID
            } else {
                roots.append(block.id)
                rootByBlockID[block.id] = block.id
            }
            seen.insert(block.id)
        }
        guard !roots.isEmpty else { throw .abort }
        return ClipboardForest(
            blocks: blocks,
            rootIDs: roots,
            blocksByID: Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) }),
            rootByBlockID: rootByBlockID
        )
    }

    private func replaceBlockSelection(
        _ blockSelection: BlockSelection,
        with forest: ClipboardForest,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        let selectedRoots = state.document.topLevelBlockIDs(blockSelection.blockIDs)
        guard
            let firstSelectedID = selectedRoots.first,
            let firstSelected = state.document.block(firstSelectedID)
        else { throw .abort }
        let targetParentID = firstSelected.parentID
        let targetIndex =
            state.document.children(of: targetParentID).firstIndex(of: firstSelectedID)
            ?? 0

        var removed: [BlockID] = []
        for blockID in selectedRoots {
            switch state.document.removeSubtree(blockID) {
            case .success(let blockIDs): removed.append(contentsOf: blockIDs)
            case .failure: throw .abort
            }
        }

        let insertedRoots = try insertFreshForest(
            forest,
            parentID: targetParentID,
            index: targetIndex,
            changed: &changed
        )
        state.selection = .blocks(BlockSelection(blockIDs: insertedRoots))
        changed.formUnion(removed)
        operations.append(.replaceDocument)
    }
}
