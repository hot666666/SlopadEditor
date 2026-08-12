@testable import SlopadEditorEngine
import SlopadCoreModel

func sessionBlockSelection(_ selection: EditorSelection) -> BlockSelection? {
    guard case .blocks(let blockSelection) = selection else { return nil }
    return blockSelection
}

func sessionCaretPosition(_ selection: EditorSelection) -> TextPosition? {
    guard case .caret(let position) = selection else { return nil }
    return position
}
