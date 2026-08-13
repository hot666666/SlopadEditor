import SlopadEditorCoreModel

// MARK: - EditorState

/// Everything an edit reads and writes, as one value.
///
/// The document is what gets persisted. Selection and stored marks are not — but they are
/// not runtime decoration either, because undo has to restore them and the next keystroke
/// depends on them. Keeping the three together gives a transaction one before-image and one
/// after-image instead of three parallel fields that can drift apart.
///
/// `EditorModel` owns the transitions; this value owns what is being transitioned.
struct EditorState {
    var document: Document

    var selection: EditorSelection

    /// Marks to apply to the next inserted text while the selection is a caret.
    ///
    /// This is why the three values travel together: it cannot live in ``document`` (it is
    /// not content), and it cannot live in the platform layer (it decides the meaning of the
    /// next edit, and undo must restore it).
    var storedMarks: Set<BlockContent.InlineMark.Kind>

    init(
        document: Document,
        selection: EditorSelection,
        storedMarks: Set<BlockContent.InlineMark.Kind> = []
    ) {
        self.document = document
        self.selection = selection
        self.storedMarks = storedMarks
    }

    /// Moves the selection somewhere the user pointed at, dropping ``storedMarks``.
    ///
    /// This is the distinction that makes stored marks usable: the caret advancing because a
    /// character was typed must *keep* them, or holding bold would style only the first
    /// letter. Navigating, clicking, or selecting elsewhere must *drop* them, because a style
    /// armed for one spot means nothing at another. Edit-driven caret moves therefore assign
    /// ``selection`` directly; only deliberate relocation comes through here.
    mutating func replaceSelection(_ newSelection: EditorSelection) {
        selection = newSelection
        storedMarks = []
    }

    /// Toggles a stored mark, so pressing bold twice at a caret leaves nothing armed.
    mutating func toggleStoredMark(_ kind: BlockContent.InlineMark.Kind) {
        if let existing = storedMarks.first(where: { $0.caseIdentity == kind.caseIdentity }) {
            storedMarks.remove(existing)
            if existing != kind {
                storedMarks.insert(kind)
            }
        } else {
            storedMarks.insert(kind)
        }
    }
}
