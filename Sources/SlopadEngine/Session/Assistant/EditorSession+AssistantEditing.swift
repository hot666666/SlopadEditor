import SlopadBlockLayout
import SlopadCoreModel
import SlopadEditorModel

// MARK: - Assistant Editing Contract

extension EditorSession {
    public func documentContextSnapshot()
        throws(EditorDocumentTransactionError) -> EditorDocumentContextSnapshot
    {
        guard composition == nil else {
            throw .activeComposition
        }
        let selection = editorModel.selection
        guard editorModel.document.validates(selection) else {
            throw .invalidSelection
        }

        let document = documentSnapshot
        return EditorDocumentContextSnapshot(
            source: EditorDocumentSource(
                sessionEpoch: documentContextEpoch,
                revision: document.revision,
                selection: selection
            ),
            document: document,
            selection: selection,
            selectedContent: selectedContent(
                selection: selection,
                document: editorModel.document
            )
        )
    }

    @discardableResult
    public func applyDocumentPatch(
        _ patch: EditorDocumentPatch
    ) throws(EditorDocumentTransactionError) -> EditorUpdate? {
        guard composition == nil else {
            throw .activeComposition
        }
        guard
            patch.source.sessionEpoch == documentContextEpoch,
            patch.source.revision == currentDocumentRevision,
            patch.source.selection == editorModel.selection
        else {
            throw .staleSource
        }

        let result: (selectionBefore: EditorSelection, change: EditorChange)?
        do {
            result = try editorModel.replaceDocument(
                with: patch.replacementBlocks,
                selection: patch.selectionAfter
            )
        } catch let error {
            throw EditorDocumentTransactionError(error)
        }

        guard let result else { return nil }

        textNavigationRuntimeContext = nil
        blockDrag = nil
        blockSelectionRectangle = nil
        blockSelectionDragAnchor = nil
        textSelectionDragAnchor = nil
        textDoubleClickSelection = nil
        if result.change.documentChanged {
            blockLayout = BlockLayout()
        }
        let invalidation = markLayoutDirty(for: result.change)
        return makeEditorUpdate(
            invalidation: invalidation,
            previousSelection: result.selectionBefore
        )
    }
}

// MARK: - Selected Content Projection

extension EditorSession {
    private func selectedContent(
        selection: EditorSelection,
        document: Document
    ) -> EditorSelectedContent {
        switch selection {
        case .inactive, .caret:
            return .none

        case .text(let textSelection):
            return .text(
                EditorSelectedText(
                    fragments: selectedTextFragments(
                        selection: textSelection,
                        document: document
                    )
                )
            )

        case .blocks(let blockSelection):
            let rootBlockIDs = document.topLevelBlockIDs(blockSelection.blockIDs)
            let selectedRoots = Set(rootBlockIDs)
            let blocks = document.editorBlockInputs.filter { input in
                document.hasAncestorOrSelf(in: selectedRoots, of: input.id)
            }
            return .blocks(
                EditorSelectedBlocks(
                    rootBlockIDs: rootBlockIDs,
                    blocks: blocks
                )
            )
        }
    }

    private func selectedTextFragments(
        selection: TextSelection,
        document: Document
    ) -> [EditorSelectedTextFragment] {
        let blocks = document.editorBlockInputs
        let indexes = Dictionary(
            uniqueKeysWithValues: blocks.enumerated().map { ($0.element.id, $0.offset) }
        )
        guard
            let anchorIndex = indexes[selection.anchor.blockID],
            let focusIndex = indexes[selection.focus.blockID]
        else { return [] }

        let start: TextPosition
        let end: TextPosition
        let startIndex: Int
        let endIndex: Int
        if anchorIndex < focusIndex
            || (anchorIndex == focusIndex && selection.anchor.offset <= selection.focus.offset)
        {
            start = selection.anchor
            end = selection.focus
            startIndex = anchorIndex
            endIndex = focusIndex
        } else {
            start = selection.focus
            end = selection.anchor
            startIndex = focusIndex
            endIndex = anchorIndex
        }

        return (startIndex...endIndex).map { index in
            let block = blocks[index]
            let sourceRange: TextRange
            if startIndex == endIndex {
                sourceRange = TextRange(start.offset, end.offset)
            } else if index == startIndex {
                sourceRange = TextRange(start.offset, block.content.length)
            } else if index == endIndex {
                sourceRange = TextRange(0, end.offset)
            } else {
                sourceRange = TextRange(0, block.content.length)
            }
            return EditorSelectedTextFragment(
                blockID: block.id,
                parentID: block.parentID,
                kind: block.kind,
                sourceRange: sourceRange,
                content: slicedContent(block.content, sourceRange: sourceRange)
            )
        }
    }

    private func slicedContent(
        _ content: BlockContent,
        sourceRange: TextRange
    ) -> BlockContent {
        let marks = content.marks.compactMap { mark -> BlockContent.InlineMark? in
            let lowerBound = max(mark.range.lowerBound, sourceRange.lowerBound)
            let upperBound = min(mark.range.upperBound, sourceRange.upperBound)
            guard lowerBound < upperBound else { return nil }
            return BlockContent.InlineMark(
                kind: mark.kind,
                range: TextRange(
                    lowerBound - sourceRange.lowerBound,
                    upperBound - sourceRange.lowerBound
                )
            )
        }
        return BlockContent(
            text: content.text.substring(in: sourceRange),
            marks: marks
        )
    }
}

extension EditorDocumentTransactionError {
    init(_ error: EditorDocumentReplacementError) {
        switch error {
        case .emptyDocument:
            self = .emptyDocument
        case .duplicateBlockID(let blockID):
            self = .duplicateBlockID(blockID)
        case .invalidContent(let blockID):
            self = .invalidContent(blockID: blockID)
        case .missingParent(let blockID, let parentID):
            self = .missingParent(blockID: blockID, parentID: parentID)
        case .cycleDetected(let blockID):
            self = .cycleDetected(blockID)
        case .noncanonicalDepthFirstOrder:
            self = .noncanonicalDepthFirstOrder
        case .invalidSelection:
            self = .invalidSelection
        }
    }
}
