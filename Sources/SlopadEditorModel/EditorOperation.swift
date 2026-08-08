import SlopadCoreModel

// MARK: - EditorOperation

package enum EditorOperation {
    case replaceDocument
    case splitBlock(original: BlockID, created: BlockID)
    case mergeBlocks(target: BlockID, source: BlockID)
    case refreshMarker
    case indent(blockIDs: [BlockID])
    case outdent(blockIDs: [BlockID])
    case moveBlocks(blockIDs: [BlockID])
    case deleteBlocks(blockIDs: [BlockID])
    case resetDocumentToEmptyParagraph(blockID: BlockID)
    /// A concrete input-rule signal, not canonical document state or a generic suggestion API.
    case openSlashCommand(blockID: BlockID, triggerRange: TextRange)
}
