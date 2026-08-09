// MARK: - EditorInputEvent

public enum EditorInputEvent: Hashable, Sendable {
    public enum Command: Hashable, Sendable {
        case insertText(String)
        case replaceText(blockID: BlockID, range: TextRange, text: String)
        case pasteText(String)
        case pasteStructured(EditorClipboardPayload)
        case cutSelection
        case deleteBackward
        case deleteForward
        case deleteToTextStart
        case enter
        case shiftEnter
        case escape
        case clearSelection
        case indent
        case outdent
        /// Movement whose result depends on where text actually landed on screen.
        ///
        /// Split out so the rest of ``Command`` is provably viewport-free: a caller with no
        /// layout — an agent, a slash menu, a test — can drive editing through every other
        /// case and the compiler will tell it where that stops being possible.
        case navigate(Navigation)
        /// Applies `style` to the active text selection, or removes it when the selection
        /// already carries that style throughout.
        ///
        /// Requires a non-empty text selection. A caret-only selection is refused, because
        /// remembering a style for the next keystroke is editing state rather than a
        /// document change.
        case toggleInlineStyle(BlockContent.InlineMark.Kind)
        /// Removes every inline mark from the active text selection.
        case clearInlineStyles
        case moveToTextStart
        case moveToTextEnd
        case extendToTextStart
        case extendToTextEnd
        case selectAll
        case undo
        case redo

        // MARK: - Navigation

        /// Movement resolved against laid-out text rather than document order.
        public enum Navigation: Hashable, Sendable {
            case deleteWordBackward(viewport: EditorViewport)
            case moveLeft(viewport: EditorViewport)
            case moveRight(viewport: EditorViewport)
            case moveWordLeft(viewport: EditorViewport)
            case moveWordRight(viewport: EditorViewport)
            case extendCharacterLeft(viewport: EditorViewport)
            case extendCharacterRight(viewport: EditorViewport)
            case extendWordLeft(viewport: EditorViewport)
            case extendWordRight(viewport: EditorViewport)
            case moveUp(viewport: EditorViewport)
            case moveDown(viewport: EditorViewport)
            case extendUp(viewport: EditorViewport)
            case extendDown(viewport: EditorViewport)
        }
    }

    public enum Pointer: Hashable, Sendable {
        case focusText(documentPoint: EditorPoint, viewport: EditorViewport)
        case beginTextSelection(documentPoint: EditorPoint, viewport: EditorViewport)
        case updateTextSelection(
            documentPoint: EditorPoint,
            viewport: EditorViewport
        )
        case endTextSelection
        case selectWordOrAllText(documentPoint: EditorPoint, viewport: EditorViewport)
        case selectBlock(
            documentPoint: EditorPoint, region: BlockHitRegion, viewport: EditorViewport)
        case beginBlockDrag(documentPoint: EditorPoint, viewport: EditorViewport)
        case updateBlockDrag(documentPoint: EditorPoint, viewport: EditorViewport)
        case endBlockDrag(documentPoint: EditorPoint, viewport: EditorViewport)
        case cancelBlockDrag
        case beginBlockSelectionRectangle(documentPoint: EditorPoint, viewport: EditorViewport)
        case updateBlockSelectionRectangle(documentPoint: EditorPoint, viewport: EditorViewport)
        case endBlockSelectionRectangle
        case extendBlockSelection(
            documentPoint: EditorPoint, region: BlockHitRegion, viewport: EditorViewport)
        case endBlockSelection
        case selectBlockRange(anchor: BlockHitTestResult, focus: BlockHitTestResult)
    }

    case command(Command)
    case pointer(Pointer)
    case activeTextSelectionChanged(blockID: BlockID, selectedRange: TextRange)
    case beginComposition(blockID: BlockID, replacementRange: TextRange, text: String)
    case updateComposition(blockID: BlockID, replacementRange: TextRange, text: String)
    case commitComposition
    case cancelComposition
}
