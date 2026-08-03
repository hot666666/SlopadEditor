import SlopadCoreModel

// MARK: - EditorChange

package struct EditorChange {
    package let documentChanged: Bool
    package let changedBlockIDs: Set<BlockID>
    package let operations: [EditorOperation]

    init(
        documentChanged: Bool = false,
        changedBlockIDs: Set<BlockID> = [],
        operations: [EditorOperation] = []
    ) {
        self.documentChanged = documentChanged
        self.changedBlockIDs = changedBlockIDs
        self.operations = operations
    }
}
