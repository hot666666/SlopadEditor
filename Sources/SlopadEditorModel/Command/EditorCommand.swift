import SlopadCoreModel

// MARK: - EditorCommand

package enum EditorCommand {
    case insertText(String)
    case replaceText(blockID: BlockID, range: TextRange, text: String)
    case deleteText(blockID: BlockID, range: TextRange)
    case indentText(blockID: BlockID, range: TextRange)
    case outdentText(blockID: BlockID, range: TextRange)
    case splitBlock(blockID: BlockID, offset: Int)
    case mergeBlocks(target: BlockID, source: BlockID)
    case setBlockKind(blockID: BlockID, kind: BlockKind)
    case applyTextStyle(blockID: BlockID, range: TextRange, style: BlockContent.InlineMark.Kind)
    case removeTextStyle(
        blockID: BlockID, range: TextRange, style: BlockContent.InlineMark.Kind.CaseIdentity)
    case toggleTextStyle(blockID: BlockID, range: TextRange, style: BlockContent.InlineMark.Kind)
    case clearTextStyles(blockID: BlockID, range: TextRange)
    case indentBlock(BlockSelection)
    case outdentBlock(BlockSelection)
    case moveBlockSelection(BlockSelection, target: BlockDropTarget)
    case toggleTodo(blockID: BlockID)
    case handleEnter
    case handleShiftEnter
    case handleBackspace
    case deleteBlockSelection
}
