// MARK: - EditorUndoConfiguration

struct EditorUndoConfiguration {
    let maxTransactions: Int
    let maxEstimatedBytes: Int

    init(maxTransactions: Int = 100, maxEstimatedBytes: Int = 32 * 1024 * 1024) {
        self.maxTransactions = maxTransactions
        self.maxEstimatedBytes = maxEstimatedBytes
    }
}
