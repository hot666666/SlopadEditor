import SlopadCoreModel

// MARK: - EditorTransactionEntry

/// One item of work inside a single transaction.
///
/// Deliberately not called a *step*: this records what the caller asked for, not an
/// invertible delta of the document. Undo replays neither of these — it restores the whole
/// before-image. A future step-based history would be a different type with different
/// obligations (apply, inverse, position mapping), and reusing the word here would make the
/// two look interchangeable.
package enum EditorTransactionEntry {
    case command(EditorCommand)
    case replaceSelection(EditorSelection)
}
