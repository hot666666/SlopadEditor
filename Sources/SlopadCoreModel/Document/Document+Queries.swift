// MARK: - Document Queries

extension Document {
    /// Projects the canonical block tree into parent-before-children public host values.
    ///
    /// Sibling order follows the canonical `rootBlockIDs` and `childIDs` arrays.
    package var editorBlockInputs: [EditorBlockInput] {
        var inputs: [EditorBlockInput] = []
        inputs.reserveCapacity(blocks.count)
        var stack = Array(rootBlockIDs.reversed())

        while let blockID = stack.popLast() {
            guard let block = blocks[blockID] else {
                preconditionFailure("Canonical document contains a missing block reference")
            }
            inputs.append(
                EditorBlockInput(
                    id: block.id,
                    parentID: block.parentID,
                    kind: block.kind,
                    content: block.content
                )
            )
            stack.append(contentsOf: block.childIDs.reversed())
        }

        return inputs
    }

    package func hasSameCanonicalContent(as other: Document) -> Bool {
        rootBlockIDs == other.rootBlockIDs && blocks == other.blocks
    }

    package var estimatedStorageBytes: Int {
        var total = rootBlockIDs.reduce(0) { $0 + $1.rawValue.utf8.count + 16 }
        for block in blocks.values {
            total += block.id.rawValue.utf8.count + 128
            total += block.parentID?.rawValue.utf8.count ?? 0
            total += block.childIDs.reduce(0) { $0 + $1.rawValue.utf8.count + 16 }
            total += block.content.text.utf8.count
            total += block.content.marks.count * 64
        }
        return total
    }

    package func block(_ blockID: BlockID) -> Block? {
        blocks[blockID]
    }

    package func containsBlock(_ blockID: BlockID) -> Bool {
        blocks[blockID] != nil
    }

    package func children(of parentID: BlockID?) -> [BlockID] {
        if let parentID {
            return blocks[parentID]?.childIDs ?? []
        }
        return rootBlockIDs
    }

    package func parentID(of blockID: BlockID) -> BlockID? {
        blocks[blockID]?.parentID
    }

    package func previousSiblingID(of blockID: BlockID) -> BlockID? {
        guard let block = blocks[blockID] else { return nil }
        let siblings = children(of: block.parentID)
        guard let index = siblings.firstIndex(of: blockID), index > 0 else { return nil }
        return siblings[index - 1]
    }

    package func blockOrderPath(for blockID: BlockID) -> [Int]? {
        guard containsBlock(blockID) else { return nil }
        var reversedIndexes: [Int] = []
        var currentID: BlockID? = blockID
        while let blockID = currentID {
            let parentID = parentID(of: blockID)
            let siblings = children(of: parentID)
            guard let index = siblings.firstIndex(of: blockID) else { return nil }
            reversedIndexes.append(index)
            currentID = parentID
        }
        return Array(reversedIndexes.reversed())
    }

    package func topLevelBlockIDs(_ blockIDs: [BlockID]) -> [BlockID] {
        let selected = Set(blockIDs)
        return
            blockIDs
            .sorted {
                (blockOrderPath(for: $0) ?? [])
                    .lexicographicallyPrecedes(blockOrderPath(for: $1) ?? [])
            }
            .filter { !hasAncestor(in: selected, of: $0) }
    }

    package func blockDepth(of blockID: BlockID) -> Int? {
        guard containsBlock(blockID) else { return nil }
        var depth = 0
        var currentParentID = parentID(of: blockID)
        while let parentID = currentParentID {
            depth += 1
            currentParentID = self.parentID(of: parentID)
        }
        return depth
    }

    package func hasAncestor(_ ancestorID: BlockID, of blockID: BlockID) -> Bool {
        var current = parentID(of: blockID)
        while let currentID = current {
            if currentID == ancestorID {
                return true
            }
            current = parentID(of: currentID)
        }
        return false
    }

    package func hasAncestor(in ancestorIDs: Set<BlockID>, of blockID: BlockID) -> Bool {
        var current = parentID(of: blockID)
        while let currentID = current {
            if ancestorIDs.contains(currentID) {
                return true
            }
            current = parentID(of: currentID)
        }
        return false
    }

    package func hasAncestorOrSelf(in blockIDs: Set<BlockID>, of blockID: BlockID) -> Bool {
        var current: BlockID? = blockID
        while let currentID = current {
            if blockIDs.contains(currentID) {
                return true
            }
            current = parentID(of: currentID)
        }
        return false
    }
}
