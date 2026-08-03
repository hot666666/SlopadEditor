import SlopadBlockLayout
import SlopadCoreModel
import SlopadEditorModel

// MARK: - Update Projection

extension EditorSession {
    func handleCommand(_ command: EditorCommand) -> EditorUpdate {
        let projection = applyCommandForUpdate(command)
        return makeEditorUpdate(
            invalidation: projection.invalidation,
            previousSelection: projection.previousSelection
        )
    }

    func applyCommandForUpdate(
        _ command: EditorCommand
    ) -> (previousSelection: EditorSelection?, invalidation: EditorUpdateInvalidation) {
        let result = editorModel.apply(command)
        if result != nil {
            textNavigationRuntimeContext = nil
        }
        let invalidation = markLayoutDirty(for: result?.change)
        return (
            previousSelection: result?.selectionBefore,
            invalidation: invalidation
        )
    }

    func markLayoutDirty(for change: EditorChange?) -> EditorUpdateInvalidation {
        guard let change else { return EditorUpdateInvalidation() }
        if change.documentChanged {
            recordDocumentChange()
        }
        let invalidations = Self.projectInvalidations(for: change)
        blockLayout.markDirty(invalidations.layout)
        return invalidations.update
    }

    func makeEditorUpdate(
        invalidation: EditorUpdateInvalidation,
        previousSelection: EditorSelection? = nil
    ) -> EditorUpdate {
        let committedDocumentRevision = takePendingDocumentRevision()
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
        return EditorUpdate(
            selection: activeEditorSelection,
            previousSelection: previousSelection,
            composition: composition,
            history: historyState,
            committedDocumentRevision: committedDocumentRevision,
            layoutDirty: blockLayout.isDirty,
            invalidation: invalidation
        )
        #else
            return EditorUpdate(
                selection: activeEditorSelection,
                previousSelection: previousSelection,
                composition: composition,
                history: historyState,
                committedDocumentRevision: committedDocumentRevision,
                invalidation: invalidation
            )
        #endif
    }
}

// MARK: - Editor Invalidation Projection

extension EditorSession {
    private static func projectInvalidations(
        for change: EditorChange
    ) -> (layout: BlockLayoutInvalidation, update: EditorUpdateInvalidation) {
        let visibleSequenceChanged = projectsVisibleSequenceChange(for: change.operations)

        return (
            layout: BlockLayoutInvalidation(
                blockIDs: change.changedBlockIDs,
                layoutGeometryChanged: visibleSequenceChanged,
                mutations: change.operations.compactMap(BlockLayoutMutation.init(operation:))
            ),
            update: EditorUpdateInvalidation(
                blockIDs: change.changedBlockIDs,
                visibleSequenceChanged: visibleSequenceChanged,
                layoutGeometryChanged: visibleSequenceChanged
            )
        )
    }

    private static func projectsVisibleSequenceChange(
        for operations: [EditorOperation]
    ) -> Bool {
        for operation in operations {
            switch operation {
            case .refreshMarker:
                continue

            case .indent(let blockIDs),
                .outdent(let blockIDs),
                .deleteBlocks(let blockIDs),
                .moveBlocks(let blockIDs):
                if !blockIDs.isEmpty { return true }

            case .replaceDocument,
                .resetDocumentToEmptyParagraph,
                .splitBlock,
                .mergeBlocks:
                return true
            }
        }
        return false
    }
}

// MARK: - Layout Mutation Projection

extension BlockLayoutMutation {
    fileprivate init?(operation: EditorOperation) {
        switch operation {
        case .replaceDocument:
            return nil
        case .splitBlock(let original, let created):
            self = .splitBlock(original: original, created: created)
        case .mergeBlocks(let target, let source):
            self = .mergeBlocks(target: target, source: source)
        case .refreshMarker:
            self = .refreshMarker
        case .indent(let blockIDs), .outdent(let blockIDs), .moveBlocks(let blockIDs):
            self = .relocateSubtrees(blockIDs: blockIDs)
        case .deleteBlocks(let blockIDs):
            self = .deleteBlocks(blockIDs: blockIDs)
        case .resetDocumentToEmptyParagraph(let blockID):
            self = .resetDocumentToEmptyParagraph(blockID: blockID)
        }
    }
}
