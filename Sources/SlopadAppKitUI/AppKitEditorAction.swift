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
    case clearSelection
    case indent
    case outdent
    /// Applies an inline style to the selected text, or removes it when the selection
    /// already carries that style throughout. Requires a non-empty text selection.
    case toggleInlineStyle(BlockContent.InlineMark.Kind)
    /// Removes every inline mark from the selected text.
    case clearInlineStyles
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
            command = .navigate(.deleteWordBackward(viewport: viewport))
        case .enter:
            command = .enter
        case .shiftEnter:
            command = .shiftEnter
        case .escape:
            command = .escape
        case .clearSelection:
            command = .clearSelection
        case .indent:
            command = .indent
        case .outdent:
            command = .outdent
        case .toggleInlineStyle(let style):
            command = .toggleInlineStyle(style)
        case .clearInlineStyles:
            command = .clearInlineStyles
        case .moveLeft:
            command = .navigate(.moveLeft(viewport: viewport))
        case .moveRight:
            command = .navigate(.moveRight(viewport: viewport))
        case .moveToTextStart:
            command = .moveToTextStart
        case .moveToTextEnd:
            command = .moveToTextEnd
        case .moveWordLeft:
            command = .navigate(.moveWordLeft(viewport: viewport))
        case .moveWordRight:
            command = .navigate(.moveWordRight(viewport: viewport))
        case .extendCharacterLeft:
            command = .navigate(.extendCharacterLeft(viewport: viewport))
        case .extendCharacterRight:
            command = .navigate(.extendCharacterRight(viewport: viewport))
        case .extendToTextStart:
            command = .extendToTextStart
        case .extendToTextEnd:
            command = .extendToTextEnd
        case .extendWordLeft:
            command = .navigate(.extendWordLeft(viewport: viewport))
        case .extendWordRight:
            command = .navigate(.extendWordRight(viewport: viewport))
        case .moveUp:
            command = .navigate(.moveUp(viewport: viewport))
        case .moveDown:
            command = .navigate(.moveDown(viewport: viewport))
        case .extendUp:
            command = .navigate(.extendUp(viewport: viewport))
        case .extendDown:
            command = .navigate(.extendDown(viewport: viewport))
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
