import SlopadCoreModel

// MARK: - EditorCommandResult

/// What applying a command actually did.
///
/// The previous shape was an optional tuple, so every caller could only ask "did anything
/// happen". Three different outcomes collapsed into `nil` or into an indistinguishable
/// non-`nil`: a command that did not apply, one that moved only the selection, and one that
/// changed the document all looked alike. Callers that care about persistence, history, or
/// layout invalidation need to tell them apart.
package enum EditorCommandResult {
    /// The command did not apply — wrong selection kind, missing block, nothing to do.
    /// No transaction was recorded.
    case notApplicable

    /// The command applied and changed the selection or the caret's armed styles, but left
    /// the document alone. There is a transaction to undo, but nothing to persist.
    case selectionOnly(EditorCommandOutcome)

    /// The command changed the document.
    case document(EditorCommandOutcome)

    /// The recorded effect, for the two cases that produced one.
    package var outcome: EditorCommandOutcome? {
        switch self {
        case .notApplicable: nil
        case .selectionOnly(let outcome), .document(let outcome): outcome
        }
    }

    /// Whether anything was applied at all.
    package var isApplied: Bool {
        outcome != nil
    }

    /// Whether the canonical document changed, and therefore whether a host has something
    /// new to persist.
    package var changedDocument: Bool {
        if case .document = self { return true }
        return false
    }
}

// MARK: - EditorCommandOutcome

package struct EditorCommandOutcome {
    package let selectionBefore: EditorSelection
    package let change: EditorChange

    init(selectionBefore: EditorSelection, change: EditorChange) {
        self.selectionBefore = selectionBefore
        self.change = change
    }
}
