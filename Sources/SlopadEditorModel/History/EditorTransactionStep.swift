import SlopadCoreModel

// MARK: - EditorTransactionStep

package enum EditorTransactionStep {
    case command(EditorCommand)
    case replaceSelection(EditorSelection)
}
