@testable import SlopadEditorEngine
import SlopadCoreModel

extension EditorSession {
    var document: Document {
        editorModel.document
    }

    convenience init(document: Document, selection: EditorSelection? = nil) {
        self.init(
            document: document,
            selection: selection,
            textLayouter: DeterministicBlockTextLayouter()
        )
    }
}
