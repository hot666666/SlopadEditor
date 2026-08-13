// MARK: - DocumentInvariantViolation

enum DocumentInvariantViolation: Hashable, Sendable {
    case invalidRootParent(BlockID, actualParent: BlockID?)
    case missingBlockReference(parent: BlockID?, child: BlockID)
    case duplicateChild(parent: BlockID?, child: BlockID)
    case parentChildMismatch(parent: BlockID?, child: BlockID, actualParent: BlockID?)
    case orphan(BlockID)
    case cycleDetected(BlockID)
    case visibleSequenceMismatch(expected: [BlockID], actual: [BlockID])
}

// MARK: - DocumentInvariantReport

struct DocumentInvariantReport: Hashable, Sendable {
    var violations: [DocumentInvariantViolation]

    init(violations: [DocumentInvariantViolation]) {
        self.violations = violations
    }

    var isValid: Bool {
        violations.isEmpty
    }
}

// MARK: - Document Invariants

extension Document {
    func validateInvariants() -> DocumentInvariantReport {
        let document = self
        var violations: [DocumentInvariantViolation] = []
        var seenEdges: Set<String> = []
        var visited: Set<BlockID> = []
        var visiting: Set<BlockID> = []

        enum TraversalFrame {
            case enter(blockID: BlockID, parentID: BlockID?)
            case exit(blockID: BlockID)
        }

        var traversalStack = rootBlockIDs.reversed().map {
            TraversalFrame.enter(blockID: $0, parentID: nil)
        }
        while let frame = traversalStack.popLast() {
            if case .exit(let blockID) = frame {
                visiting.remove(blockID)
                visited.insert(blockID)
                continue
            }
            guard case .enter(let blockID, let parentID) = frame else { continue }

            let key = "\(parentID?.rawValue ?? "root")->\(blockID.rawValue)"
            if seenEdges.contains(key) {
                violations.append(.duplicateChild(parent: parentID, child: blockID))
                continue
            }
            seenEdges.insert(key)

            guard let block = document.blocks[blockID] else {
                violations.append(.missingBlockReference(parent: parentID, child: blockID))
                continue
            }
            if visiting.contains(blockID) {
                violations.append(.cycleDetected(blockID))
                continue
            }
            if visited.contains(blockID) {
                violations.append(.duplicateChild(parent: parentID, child: blockID))
                continue
            }

            if block.parentID != parentID {
                if parentID == nil {
                    violations.append(.invalidRootParent(blockID, actualParent: block.parentID))
                } else {
                    violations.append(
                        .parentChildMismatch(
                            parent: parentID, child: blockID, actualParent: block.parentID))
                }
            }

            visiting.insert(blockID)
            traversalStack.append(.exit(blockID: blockID))
            for childID in block.childIDs.reversed() {
                traversalStack.append(.enter(blockID: childID, parentID: blockID))
            }
        }

        for blockID in document.blocks.keys where !visited.contains(blockID) {
            violations.append(.orphan(blockID))
        }

        let visible = Self.uniqueReferencedPreorder(document)
        let rawPreorder = Self.rawReferencedPreorder(document)
        if visible != rawPreorder {
            violations.append(.visibleSequenceMismatch(expected: rawPreorder, actual: visible))
        }

        return DocumentInvariantReport(violations: violations)
    }

    package func assertValidInvariants(file: StaticString = #fileID, line: UInt = #line) {
        let report = validateInvariants()
        precondition(
            report.isValid,
            "Invalid document invariants: \(report.violations)",
            file: file,
            line: line
        )
    }

    private static func rawReferencedPreorder(_ document: Document) -> [BlockID] {
        var output: [BlockID] = []
        let limit = max(1, document.blocks.count * 2 + document.rootBlockIDs.count + 1)

        var stack = Array(document.rootBlockIDs.reversed())
        while let blockID = stack.popLast(), output.count < limit {
            output.append(blockID)
            if let block = document.blocks[blockID] {
                stack.append(contentsOf: block.childIDs.reversed())
            }
        }
        return output
    }

    private static func uniqueReferencedPreorder(_ document: Document) -> [BlockID] {
        var output: [BlockID] = []
        var visited: Set<BlockID> = []

        var stack = Array(document.rootBlockIDs.reversed())
        while let blockID = stack.popLast() {
            guard visited.insert(blockID).inserted else { continue }
            output.append(blockID)
            if let block = document.blocks[blockID] {
                stack.append(contentsOf: block.childIDs.reversed())
            }
        }
        return output
    }
}
