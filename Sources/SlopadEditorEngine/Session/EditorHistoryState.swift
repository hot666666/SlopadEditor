// MARK: - EditorHistoryState

public struct EditorHistoryState: Sendable {
    public let canUndo: Bool
    public let canRedo: Bool

    init(canUndo: Bool, canRedo: Bool) {
        self.canUndo = canUndo
        self.canRedo = canRedo
    }
}
