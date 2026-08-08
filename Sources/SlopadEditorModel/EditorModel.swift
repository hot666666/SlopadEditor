import SlopadCoreModel
import SlopadMarkdownInputRules

// MARK: - EditorModel

package final class EditorModel {
    /// The value being edited. Mutated only from inside this module; transitions and history
    /// are this class's job.
    var state: EditorState

    package var document: Document { state.document }
    package var selection: EditorSelection { state.selection }
    package var storedMarks: Set<BlockContent.InlineMark.Kind> { state.storedMarks }

    let undoConfiguration: EditorUndoConfiguration
    var undoStack: [EditorTransaction]
    var redoStack: [EditorTransaction]
    /// Runtime-owned bounded matcher. The patterns are injected as immutable data from the
    /// lightweight Markdown syntax target; the model keeps transaction semantics local.
    let inputRuleRunner: EditorInputRuleRunner

    package convenience init(
        document: Document,
        selection: EditorSelection? = nil
    ) {
        self.init(
            document: document,
            selection: selection,
            undoConfiguration: EditorUndoConfiguration()
        )
    }

    init(
        document: Document,
        selection: EditorSelection? = nil,
        undoConfiguration: EditorUndoConfiguration = EditorUndoConfiguration()
    ) {
        self.undoConfiguration = undoConfiguration
        self.inputRuleRunner = EditorInputRuleRunner(rules: MarkdownInputRules.all)
        if let selection {
            state = EditorState(document: document, selection: selection)
        } else if let firstID = document.rootBlockIDs.first {
            state = EditorState(
                document: document,
                selection: .caret(
                    blockID: firstID, offset: document.block(firstID)?.content.length ?? 0)
            )
        } else {
            let id = BlockID()
            state = EditorState(
                document: Document.singleParagraph("", id: id),
                selection: .caret(blockID: id, offset: 0)
            )
        }
        self.undoStack = []
        self.redoStack = []
    }
}
