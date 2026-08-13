// MARK: - Document Store

package struct Document: Hashable, Codable, Sendable {
    package var rootBlockIDs: [BlockID]
    package var blocks: [BlockID: Block]
    package var revision: Int

    package init() {
        rootBlockIDs = []
        blocks = [:]
        revision = 0
    }

    init(rootBlockIDs: [BlockID], blocks: [BlockID: Block], revision: Int = 0) {
        self.init(uncheckedRootBlockIDs: rootBlockIDs, blocks: blocks, revision: revision)
        assertValidInvariants()
    }

    package init(blockInputs: [EditorBlockInput], revision: Int = 0) {
        let records = Dictionary(uniqueKeysWithValues: blockInputs.map { ($0.id, $0) })
        precondition(
            records.count == blockInputs.count,
            "EditorBlockInput ids must be unique"
        )

        var rootBlockIDs: [BlockID] = []
        var childIDsByParent: [BlockID: [BlockID]] = [:]
        for record in blockInputs {
            if let parentID = record.parentID {
                precondition(
                    records[parentID] != nil,
                    "EditorBlockInput parentID must reference another input block"
                )
                childIDsByParent[parentID, default: []].append(record.id)
            } else {
                rootBlockIDs.append(record.id)
            }
        }

        let blocks = Dictionary(
            uniqueKeysWithValues: blockInputs.map { record in
                (
                    record.id,
                    Block(
                        id: record.id,
                        parentID: record.parentID,
                        childIDs: childIDsByParent[record.id] ?? [],
                        kind: record.kind,
                        content: record.content
                    )
                )
            })
        self.init(rootBlockIDs: rootBlockIDs, blocks: blocks, revision: revision)
    }

    init(
        uncheckedRootBlockIDs rootBlockIDs: [BlockID], blocks: [BlockID: Block], revision: Int = 0
    ) {
        self.rootBlockIDs = rootBlockIDs
        self.blocks = blocks
        self.revision = revision
    }

    // MARK: - Creation

    package static func singleParagraph(_ text: String = "", id: BlockID = BlockID()) -> Document {
        let block = Block(id: id, content: BlockContent(text: text))
        return Document(rootBlockIDs: [id], blocks: [id: block])
    }
}
