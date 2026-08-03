// MARK: - EditorInputEvent

public enum EditorInputEvent: Hashable, Sendable {
    public enum Command: Hashable, Sendable {
        case insertText(String)
        case replaceText(blockID: BlockID, range: TextRange, text: String)
        case pasteText(String)
        case cutSelection
        case deleteBackward
        case deleteForward
        case deleteToTextStart
        case deleteWordBackward(viewport: EditorViewport)
        case enter
        case shiftEnter
        case escape
        case indent
        case outdent
        case moveLeft(viewport: EditorViewport)
        case moveRight(viewport: EditorViewport)
        case moveToTextStart
        case moveToTextEnd
        case moveWordLeft(viewport: EditorViewport)
        case moveWordRight(viewport: EditorViewport)
        case extendCharacterLeft(viewport: EditorViewport)
        case extendCharacterRight(viewport: EditorViewport)
        case extendToTextStart
        case extendToTextEnd
        case extendWordLeft(viewport: EditorViewport)
        case extendWordRight(viewport: EditorViewport)
        case moveUp(viewport: EditorViewport)
        case moveDown(viewport: EditorViewport)
        case extendUp(viewport: EditorViewport)
        case extendDown(viewport: EditorViewport)
        case selectAll
        case undo
        case redo
    }

    public enum Pointer: Hashable, Sendable {
        case focusText(documentPoint: EditorPoint, viewport: EditorViewport)
        case beginTextSelection(documentPoint: EditorPoint, viewport: EditorViewport)
        case updateTextSelection(
            documentPoint: EditorPoint,
            viewport: EditorViewport,
            blockSelectionThreshold: Double?
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
