// MARK: - Document ContentMutation

extension Document {
    package mutating func replaceContent(
        blockID: BlockID,
        content: BlockContent
    ) -> Result<Void, DocumentMutationResult.Failure> {
        guard blocks[blockID] != nil else { return .failure(.missingBlock(blockID)) }
        blocks[blockID]?.content = content
        revision += 1
        return .success(())
    }

    package mutating func updateContent(
        blockID: BlockID,
        _ mutate: (inout BlockContent) -> Void
    ) -> Result<Void, DocumentMutationResult.Failure> {
        guard var content = blocks[blockID]?.content else {
            return .failure(.missingBlock(blockID))
        }
        mutate(&content)
        blocks[blockID]?.content = content
        revision += 1
        return .success(())
    }

    package mutating func setBlockKind(
        blockID: BlockID,
        kind: BlockKind
    ) -> Result<Void, DocumentMutationResult.Failure> {
        guard blocks[blockID] != nil else { return .failure(.missingBlock(blockID)) }
        blocks[blockID]?.kind = kind
        revision += 1
        return .success(())
    }

}
