// MARK: - DocumentMutationResult

package enum DocumentMutationResult {
    package enum Failure: Hashable, Error, Sendable {
        case missingBlock(BlockID)
        case duplicateBlock(BlockID)
        case wouldCreateCycle(BlockID)
    }

    package struct Split: Hashable, Sendable {
        package let transferredChildIDs: [BlockID]
        package let splitOffset: Int
    }

    package struct Merge: Hashable, Sendable {
        package let targetOriginalLength: Int
        package let appendedChildIDs: [BlockID]
    }
}
