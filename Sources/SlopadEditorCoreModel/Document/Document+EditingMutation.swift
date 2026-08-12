// MARK: - Document EditingMutation

extension Document {
    package mutating func splitBlock(
        blockID: BlockID,
        offset: Int,
        newBlockID: BlockID = BlockID()
    ) -> Result<DocumentMutationResult.Split, DocumentMutationResult.Failure> {
        guard let block = blocks[blockID] else { return .failure(.missingBlock(blockID)) }
        guard blocks[newBlockID] == nil else { return .failure(.duplicateBlock(newBlockID)) }

        let clampedOffset = TextRange.point(offset).clamped(to: block.content.length).lowerBound
        let prefixText = block.content.text.substring(in: TextRange(0, clampedOffset))
        let suffixText = block.content.text.substring(
            in: TextRange(clampedOffset, block.content.length))
        var prefixMarks: [BlockContent.InlineMark] = []
        var suffixMarks: [BlockContent.InlineMark] = []
        for mark in block.content.marks {
            if mark.range.lowerBound < clampedOffset {
                let upper = min(mark.range.upperBound, clampedOffset)
                if upper > mark.range.lowerBound {
                    prefixMarks.append(
                        BlockContent.InlineMark(
                            kind: mark.kind,
                            range: TextRange(mark.range.lowerBound, upper)
                        ))
                }
            }
            if mark.range.upperBound > clampedOffset {
                let lower = max(mark.range.lowerBound, clampedOffset)
                if mark.range.upperBound > lower {
                    suffixMarks.append(
                        BlockContent.InlineMark(
                            kind: mark.kind,
                            range: TextRange(
                                lower - clampedOffset, mark.range.upperBound - clampedOffset)
                        ))
                }
            }
        }

        let transferredChildren = block.childIDs
        blocks[blockID]?.content = BlockContent(
            text: prefixText,
            marks: prefixMarks,
            revision: block.content.revision + 1
        )
        blocks[blockID]?.childIDs = []

        let newBlock = Block(
            id: newBlockID,
            parentID: block.parentID,
            childIDs: transferredChildren,
            kind: block.kind.continuationKindAfterSplit,
            content: BlockContent(text: suffixText, marks: suffixMarks)
        )
        blocks[newBlockID] = newBlock
        for childID in transferredChildren {
            blocks[childID]?.parentID = newBlockID
        }
        var siblings = children(of: block.parentID)
        let insertionIndex = (siblings.firstIndex(of: blockID) ?? siblings.count - 1) + 1
        siblings.insert(newBlockID, at: min(insertionIndex, siblings.count))
        replaceChildListWithoutRevision(siblings, of: block.parentID)
        revision += 1
        return .success(
            DocumentMutationResult.Split(
                transferredChildIDs: transferredChildren,
                splitOffset: clampedOffset
            )
        )
    }

    package mutating func mergeBlocks(
        target: BlockID,
        source: BlockID
    ) -> Result<DocumentMutationResult.Merge, DocumentMutationResult.Failure> {
        guard let targetBlock = blocks[target] else { return .failure(.missingBlock(target)) }
        guard let sourceBlock = blocks[source] else { return .failure(.missingBlock(source)) }
        let targetLength = targetBlock.content.length
        var mergedContent = targetBlock.content
        mergedContent.insert(sourceBlock.content.text, at: targetLength)
        for mark in sourceBlock.content.marks {
            mergedContent.addMark(kind: mark.kind, range: mark.range.shifted(by: targetLength))
        }
        blocks[target]?.content = mergedContent

        let appendedChildren = sourceBlock.childIDs
        blocks[target]?.childIDs.append(contentsOf: appendedChildren)
        for childID in appendedChildren {
            blocks[childID]?.parentID = target
        }
        removeFromParentChildListWithoutRevision(source)
        blocks.removeValue(forKey: source)
        revision += 1
        return .success(
            DocumentMutationResult.Merge(
                targetOriginalLength: targetLength,
                appendedChildIDs: appendedChildren
            )
        )
    }
}
