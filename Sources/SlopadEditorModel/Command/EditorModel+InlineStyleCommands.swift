import SlopadCoreModel

// MARK: - Inline Style Commands

extension EditorModel {
    func applyTextStyle(
        blockID: BlockID,
        range: TextRange,
        style: BlockContent.InlineMark.Kind,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard let block = document.block(blockID) else { throw .abort }
        let originalContent = block.content
        var nextContent = originalContent
        nextContent.addMark(kind: style, range: range)
        guard nextContent.marks != originalContent.marks else {
            throw .abort
        }
        try requireDocumentMutationSuccess(
            document.replaceContent(blockID: blockID, content: nextContent))
        changed.insert(blockID)
    }

    func removeTextStyle(
        blockID: BlockID,
        range: TextRange,
        style: BlockContent.InlineMark.Kind.CaseIdentity,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard let block = document.block(blockID) else { throw .abort }
        let originalContent = block.content
        var nextContent = originalContent
        nextContent.clearMarks(matching: style, in: range)
        guard nextContent.marks != originalContent.marks else {
            throw .abort
        }
        try requireDocumentMutationSuccess(
            document.replaceContent(blockID: blockID, content: nextContent))
        changed.insert(blockID)
    }

    /// Applies `style` unless the range already carries that style throughout, in which
    /// case it is removed.
    ///
    /// Coverage is measured on the case identity, so toggling a link removes whatever link
    /// is present rather than only an exactly matching destination. A partially styled
    /// range is completed rather than cleared.
    func toggleTextStyle(
        blockID: BlockID,
        range: TextRange,
        style: BlockContent.InlineMark.Kind,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard let block = document.block(blockID) else { throw .abort }
        if block.content.coversEntirely(style.caseIdentity, in: range) {
            try removeTextStyle(
                blockID: blockID,
                range: range,
                style: style.caseIdentity,
                operations: &operations,
                changed: &changed
            )
        } else {
            try applyTextStyle(
                blockID: blockID,
                range: range,
                style: style,
                operations: &operations,
                changed: &changed
            )
        }
    }

    func clearTextStyles(
        blockID: BlockID,
        range: TextRange,
        operations: inout [EditorOperation],
        changed: inout Set<BlockID>
    ) throws(EditorCommandAbort) {
        guard let block = document.block(blockID) else { throw .abort }
        let originalContent = block.content
        var nextContent = originalContent
        nextContent.clearMarks(in: range)
        guard nextContent.marks != originalContent.marks else {
            throw .abort
        }
        try requireDocumentMutationSuccess(
            document.replaceContent(blockID: blockID, content: nextContent))
        changed.insert(blockID)
    }
}
