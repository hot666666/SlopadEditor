import SlopadEngine

// MARK: - AppKitEditorAction

/// A synchronized programmatic action on the default AppKit editor surface.
///
/// Native key, pointer, and IME callbacks remain adapter-owned. Actions that need visible
/// geometry receive the controller's current viewport when they are performed.
public enum AppKitEditorAction: Hashable, Sendable {
    case insertText(String)
    case replaceText(blockID: BlockID, range: TextRange, text: String)
    case pasteText(String)
    case cutSelection
    case deleteBackward
    case deleteToTextStart
    case deleteWordBackward
    case enter
    case shiftEnter
    case escape
    case indent
    case outdent
    case moveLeft
    case moveRight
    case moveToTextStart
    case moveToTextEnd
    case moveWordLeft
    case moveWordRight
    case extendCharacterLeft
    case extendCharacterRight
    case extendToTextStart
    case extendToTextEnd
    case extendWordLeft
    case extendWordRight
    case moveUp
    case moveDown
    case extendUp
    case extendDown
    case selectAll
    case undo
    case redo

    func inputEvent(viewport: EditorViewport) -> EditorInputEvent {
        let command: EditorInputEvent.Command
        switch self {
        case .insertText(let text):
            command = .insertText(text)
        case .replaceText(let blockID, let range, let text):
            command = .replaceText(blockID: blockID, range: range, text: text)
        case .pasteText(let text):
            command = .pasteText(text)
        case .cutSelection:
            command = .cutSelection
        case .deleteBackward:
            command = .deleteBackward
        case .deleteToTextStart:
            command = .deleteToTextStart
        case .deleteWordBackward:
            command = .deleteWordBackward(viewport: viewport)
        case .enter:
            command = .enter
        case .shiftEnter:
            command = .shiftEnter
        case .escape:
            command = .escape
        case .indent:
            command = .indent
        case .outdent:
            command = .outdent
        case .moveLeft:
            command = .moveLeft(viewport: viewport)
        case .moveRight:
            command = .moveRight(viewport: viewport)
        case .moveToTextStart:
            command = .moveToTextStart
        case .moveToTextEnd:
            command = .moveToTextEnd
        case .moveWordLeft:
            command = .moveWordLeft(viewport: viewport)
        case .moveWordRight:
            command = .moveWordRight(viewport: viewport)
        case .extendCharacterLeft:
            command = .extendCharacterLeft(viewport: viewport)
        case .extendCharacterRight:
            command = .extendCharacterRight(viewport: viewport)
        case .extendToTextStart:
            command = .extendToTextStart
        case .extendToTextEnd:
            command = .extendToTextEnd
        case .extendWordLeft:
            command = .extendWordLeft(viewport: viewport)
        case .extendWordRight:
            command = .extendWordRight(viewport: viewport)
        case .moveUp:
            command = .moveUp(viewport: viewport)
        case .moveDown:
            command = .moveDown(viewport: viewport)
        case .extendUp:
            command = .extendUp(viewport: viewport)
        case .extendDown:
            command = .extendDown(viewport: viewport)
        case .selectAll:
            command = .selectAll
        case .undo:
            command = .undo
        case .redo:
            command = .redo
        }
        return .command(command)
    }
}
