import SlopadCoreModel

// MARK: - EditorModel Selection

extension EditorModel {
    /// Moves the selection because the user aimed somewhere — navigation, a click, a
    /// programmatic reveal. Drops stored marks; see ``EditorState/replaceSelection(_:)``.
    package func replaceSelection(_ selection: EditorSelection) {
        let previousSelection = state.selection
        let previousStoredMarks = state.storedMarks
        state.replaceSelection(selection)
        recordSelectionChange(from: previousSelection)
        recordStoredMarksChange(from: previousStoredMarks)
    }
}
