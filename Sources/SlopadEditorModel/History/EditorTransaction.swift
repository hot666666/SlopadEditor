import SlopadCoreModel

// MARK: - EditorTransaction

/// One atomic edit, as the state before it and the state after it.
///
/// Carrying whole ``EditorState`` values rather than parallel document and selection fields
/// means undo restores everything an edit touched — including stored marks — without the
/// call site having to remember which pieces exist.
struct EditorTransaction {
    let before: EditorState
    let after: EditorState
    let change: EditorChange

    init(before: EditorState, after: EditorState, change: EditorChange) {
        self.before = before
        self.after = after
        self.change = change
    }

    var selectionBefore: EditorSelection { before.selection }
    var selectionAfter: EditorSelection { after.selection }

    var estimatedUndoCost: Int {
        before.document.estimatedStorageBytes
            + after.document.estimatedStorageBytes
            + change.operations.count * 96
            + change.changedBlockIDs.reduce(0) { $0 + $1.rawValue.utf8.count + 16 }
    }
}
