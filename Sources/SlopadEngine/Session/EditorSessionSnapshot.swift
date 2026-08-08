import SlopadCoreModel

// MARK: - EditorSessionSnapshot

public struct EditorSessionSnapshot: Sendable {
    public let revision: EditorSnapshotRevision
    public let totalHeight: Double
    public let visibleBlocks: [EditorRenderedBlock]
    public let selection: EditorSelection
    public let composition: TextComposition?
    public let history: EditorHistoryState
    public let activeTextInput: EditorSessionActiveTextInputDescriptor?
    /// Runtime-only `/` command interpretation for the current caret, if any.
    package let slashCommand: EditorSlashCommandPresentation?
    public let blockDragState: EditorBlockDragState?
    public let blockSelectionRectangleState: EditorBlockSelectionRectangleState?

    init(
        revision: EditorSnapshotRevision,
        totalHeight: Double,
        visibleBlocks: [EditorRenderedBlock],
        selection: EditorSelection,
        composition: TextComposition? = nil,
        history: EditorHistoryState,
        activeTextInput: EditorSessionActiveTextInputDescriptor? = nil,
        slashCommand: EditorSlashCommandPresentation? = nil,
        blockDragState: EditorBlockDragState? = nil,
        blockSelectionRectangleState: EditorBlockSelectionRectangleState? = nil
    ) {
        self.revision = revision
        self.totalHeight = totalHeight
        self.visibleBlocks = visibleBlocks
        self.selection = selection
        self.composition = composition
        self.history = history
        self.activeTextInput = activeTextInput
        self.slashCommand = slashCommand
        self.blockDragState = blockDragState
        self.blockSelectionRectangleState = blockSelectionRectangleState
    }
}
