// MARK: - Canonical Document Replacement Validation

package enum CanonicalDocumentReplacementValidationError: Error, Hashable, Sendable {
    case emptyDocument
    case duplicateBlockID(BlockID)
    case invalidContent(blockID: BlockID)
    case missingParent(blockID: BlockID, parentID: BlockID)
    case cycleDetected(BlockID)
    case noncanonicalDepthFirstOrder
    case invalidSelection
}

extension Document {
    package static func validateCanonicalReplacement(
        blockInputs: [EditorBlockInput],
        selection: EditorSelection
    ) throws(CanonicalDocumentReplacementValidationError) {
        guard !blockInputs.isEmpty else {
            throw .emptyDocument
        }

        var records: [BlockID: EditorBlockInput] = [:]
        records.reserveCapacity(blockInputs.count)
        for input in blockInputs {
            guard records.updateValue(input, forKey: input.id) == nil else {
                throw .duplicateBlockID(input.id)
            }
        }

        for input in blockInputs {
            guard input.content.isCanonical else {
                throw .invalidContent(blockID: input.id)
            }
            if let parentID = input.parentID, records[parentID] == nil {
                throw .missingParent(blockID: input.id, parentID: parentID)
            }
        }

        var visitedParentChains: Set<BlockID> = []
        visitedParentChains.reserveCapacity(blockInputs.count)
        for input in blockInputs {
            guard !visitedParentChains.contains(input.id) else { continue }

            var path: [BlockID] = []
            var pathIndexes: [BlockID: Int] = [:]
            var currentID: BlockID? = input.id
            while let blockID = currentID, !visitedParentChains.contains(blockID) {
                guard pathIndexes.updateValue(path.count, forKey: blockID) == nil else {
                    throw .cycleDetected(blockID)
                }
                path.append(blockID)
                currentID = records[blockID]?.parentID
            }
            visitedParentChains.formUnion(path)
        }

        var rootBlockIDs: [BlockID] = []
        var childIDsByParent: [BlockID: [BlockID]] = [:]
        for input in blockInputs {
            if let parentID = input.parentID {
                childIDsByParent[parentID, default: []].append(input.id)
            } else {
                rootBlockIDs.append(input.id)
            }
        }

        var canonicalOrder: [BlockID] = []
        canonicalOrder.reserveCapacity(blockInputs.count)
        var stack = Array(rootBlockIDs.reversed())
        while let blockID = stack.popLast() {
            canonicalOrder.append(blockID)
            stack.append(contentsOf: (childIDsByParent[blockID] ?? []).reversed())
        }

        guard canonicalOrder == blockInputs.map(\.id) else {
            throw .noncanonicalDepthFirstOrder
        }

        let contentLengths = Dictionary(
            uniqueKeysWithValues: blockInputs.map { ($0.id, $0.content.length) }
        )
        guard isValid(selection: selection, contentLengths: contentLengths) else {
            throw .invalidSelection
        }
    }

    package func validates(_ selection: EditorSelection) -> Bool {
        let contentLengths = blocks.mapValues(\.content.length)
        return Self.isValid(selection: selection, contentLengths: contentLengths)
    }

    private static func isValid(
        selection: EditorSelection,
        contentLengths: [BlockID: Int]
    ) -> Bool {
        func isValid(_ position: TextPosition) -> Bool {
            guard let length = contentLengths[position.blockID] else { return false }
            return (0...length).contains(position.offset)
        }

        switch selection {
        case .inactive:
            return true

        case .caret(let position):
            return isValid(position)

        case .text(let textSelection):
            return isValid(textSelection.anchor) && isValid(textSelection.focus)

        case .blocks(let blockSelection):
            let blockIDs = blockSelection.blockIDs
            return !blockIDs.isEmpty
                && Set(blockIDs).count == blockIDs.count
                && blockIDs.allSatisfy { contentLengths[$0] != nil }
                && blockIDs.contains(blockSelection.anchor)
                && blockIDs.contains(blockSelection.focus)
        }
    }
}
