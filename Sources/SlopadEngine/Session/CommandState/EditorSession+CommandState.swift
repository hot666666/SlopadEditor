import SlopadCoreModel
import SlopadEditorModel

// MARK: - EditorSession Command State

extension EditorSession {
    package func commandState() -> EditorCommandState {
        if hasLiveSelectionGesture {
            return lightweightCommandState(for: activeEditorSelection)
        }

        let key = CommandStateCacheKey(
            committedDocumentRevision: currentDocumentRevision,
            selectionIdentity: editorModel.selectionIdentity,
            storedMarksIdentity: editorModel.storedMarksIdentity,
            compositionIdentity: commandCompositionIdentity
        )
        if let cachedCommandState, cachedCommandState.key == key {
            return cachedCommandState.value
        }

        let selection = activeEditorSelection
        let value = richCommandState(for: selection)
        cachedCommandState = (key, value)
        commandStateRichProjectionCount += 1
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            benchmarkMetrics.commandStateRichProjectionCount += 1
        #endif
        return value
    }

    package func todoState(blockID: BlockID) -> EditorToggleState {
        guard blockDrag == nil else { return .unavailable }
        guard let block = editorModel.document.block(blockID) else { return .unavailable }
        switch block.kind {
        case .todo(let isChecked):
            return isChecked ? .on : .off
        default:
            return .unavailable
        }
    }

    @discardableResult
    package func toggleTodo(blockID: BlockID) -> EditorUpdate? {
        // Revalidate both identity and kind immediately before the model transaction.
        guard todoState(blockID: blockID) != .unavailable else { return nil }
        let result = editorModel.apply(.toggleTodo(blockID: blockID))
        guard result.isApplied else { return nil }
        textNavigationRuntimeContext = nil
        let invalidation = markLayoutDirty(for: result.outcome?.change)
        return makeEditorUpdate(
            invalidation: invalidation,
            previousSelection: result.outcome?.selectionBefore
        )
    }

    @discardableResult
    package func apply(_ action: EditorCommandAction) -> EditorUpdate? {
        // Session-level package actions do not implicitly mutate composition. The AppKit
        // synchronized action boundary may commit first, then calls back into this resolver.
        guard composition == nil, blockDrag == nil else { return nil }
        guard let targets = editorModel.resolveCommandTargets() else { return nil }

        switch action {
        case .toggleInlineStyle(let style):
            return applyInlineStyle(style, to: targets)

        case .clearInlineStyles:
            return clearInlineStyles(in: targets)

        case .setBlockKind(let kind):
            let blockIDs = targets.structuralBlockIDs
            guard editorModel.canSetBlockKind(kind, blockIDs: blockIDs) else { return nil }
            return handleTransaction(
                blockIDs.compactMap { blockID in
                    guard editorModel.document.block(blockID)?.kind != kind else { return nil }
                    return .command(.setBlockKind(blockID: blockID, kind: kind))
                }
            )

        case .indentBlocks:
            let blockIDs = targets.structuralBlockIDs
            guard editorModel.canIndentBlocks(blockIDs) else { return nil }
            return handleTransaction([
                .command(.indentBlock(BlockSelection(blockIDs: blockIDs))),
                .replaceSelection(targets.selection),
            ])

        case .outdentBlocks:
            let blockIDs = targets.structuralBlockIDs
            guard editorModel.canOutdentBlocks(blockIDs) else { return nil }
            return handleTransaction([
                .command(.outdentBlock(BlockSelection(blockIDs: blockIDs))),
                .replaceSelection(targets.selection),
            ])
        }
    }

    private var hasLiveSelectionGesture: Bool {
        blockDrag != nil
            || textSelectionDragAnchor != nil
            || textSelectionPendingOrigin != nil
            || blockSelectionDragAnchor != nil
            || blockSelectionRectangle != nil
    }

    private func lightweightCommandState(
        for selection: EditorSelection
    ) -> EditorCommandState {
        EditorCommandState(
            selectionMode: commandSelectionMode(for: selection),
            detail: .lightweight,
            inlineStyleAvailability: .unavailable,
            clearInlineStylesAvailability: .unavailable,
            inlineStyles: Self.unavailableInlineStyles,
            blockKind: .unavailable,
            indentBlocksAvailability: .unavailable,
            outdentBlocksAvailability: .unavailable
        )
    }

    private func richCommandState(for selection: EditorSelection) -> EditorCommandState {
        // The canonical document remains the query source during an overlay composition.
        // Availability communicates that an adapter must commit before applying.
        let resolutionSelection = composition == nil ? selection : editorModel.selection
        guard let targets = editorModel.resolveCommandTargets(for: resolutionSelection) else {
            return unavailableRichCommandState(for: selection)
        }

        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            benchmarkMetrics.commandStateVisitedBlockCount += targets.blockFactIDs.count
        #endif

        let compositionAvailability: EditorActionAvailability =
            composition == nil ? .available : .availableAfterCompositionCommit
        let inlineStyles = aggregateInlineStyles(in: targets)
        let hasInlineTarget = inlineStyles.values.contains { $0 != .unavailable }
        let hasClearableInlineStyle = hasAnyInlineStyle(in: targets)
        let kinds = targets.blockFactIDs.compactMap {
            editorModel.document.block($0)?.kind
        }
        let blockKind: EditorMixedValue<BlockKind>
        if let first = kinds.first, kinds.count == targets.blockFactIDs.count {
            blockKind = kinds.dropFirst().allSatisfy { $0 == first } ? .value(first) : .mixed
        } else {
            blockKind = .unavailable
        }

        return EditorCommandState(
            selectionMode: commandSelectionMode(for: resolutionSelection),
            detail: .rich,
            inlineStyleAvailability: hasInlineTarget
                ? compositionAvailability : .unavailable,
            clearInlineStylesAvailability: hasClearableInlineStyle
                ? compositionAvailability : .unavailable,
            inlineStyles: inlineStyles,
            blockKind: blockKind,
            indentBlocksAvailability: editorModel.canIndentBlocks(targets.structuralBlockIDs)
                ? compositionAvailability : .unavailable,
            outdentBlocksAvailability: editorModel.canOutdentBlocks(targets.structuralBlockIDs)
                ? compositionAvailability : .unavailable
        )
    }

    private func unavailableRichCommandState(
        for selection: EditorSelection
    ) -> EditorCommandState {
        EditorCommandState(
            selectionMode: commandSelectionMode(for: selection),
            detail: .rich,
            inlineStyleAvailability: .unavailable,
            clearInlineStylesAvailability: .unavailable,
            inlineStyles: Self.unavailableInlineStyles,
            blockKind: .unavailable,
            indentBlocksAvailability: .unavailable,
            outdentBlocksAvailability: .unavailable
        )
    }

    private func aggregateInlineStyles(
        in targets: ResolvedCommandTargets
    ) -> [BlockContent.InlineMark.Kind.CaseIdentity: EditorToggleState] {
        guard let inlineTarget = targets.inlineTarget else {
            return Self.unavailableInlineStyles
        }
        switch inlineTarget {
        case .caret:
            return Dictionary(
                uniqueKeysWithValues: Self.inlineStyleIdentities.map { identity in
                    let isOn = editorModel.storedMarks.contains {
                        $0.caseIdentity == identity
                    }
                    return (identity, isOn ? .on : .off)
                })

        case .fragments(let fragments):
            return Dictionary(
                uniqueKeysWithValues: Self.inlineStyleIdentities.map { identity in
                    var coveredLength = 0
                    var totalLength = 0
                    for fragment in fragments {
                        guard let block = editorModel.document.block(fragment.blockID) else {
                            continue
                        }
                        totalLength += fragment.range.length
                        coveredLength += coveredCharacterCount(
                            identity,
                            in: fragment.range,
                            content: block.content
                        )
                    }
                    let state: EditorToggleState
                    if totalLength == 0 {
                        state = .unavailable
                    } else if coveredLength == 0 {
                        state = .off
                    } else if coveredLength == totalLength {
                        state = .on
                    } else {
                        state = .mixed
                    }
                    return (identity, state)
                })
        }
    }

    private func coveredCharacterCount(
        _ identity: BlockContent.InlineMark.Kind.CaseIdentity,
        in range: TextRange,
        content: BlockContent
    ) -> Int {
        let covered = content.marks.compactMap { mark -> TextRange? in
            guard mark.kind.caseIdentity == identity else { return nil }
            let lower = max(range.lowerBound, mark.range.lowerBound)
            let upper = min(range.upperBound, mark.range.upperBound)
            return lower < upper ? TextRange(lower, upper) : nil
        }.sorted { $0.lowerBound < $1.lowerBound }
        var total = 0
        var current: TextRange?
        for next in covered {
            guard let accumulated = current else {
                current = next
                continue
            }
            if accumulated.intersects(next) || accumulated.isAdjacent(to: next) {
                current = TextRange(
                    accumulated.lowerBound,
                    max(accumulated.upperBound, next.upperBound)
                )
            } else {
                total += accumulated.length
                current = next
            }
        }
        return total + (current?.length ?? 0)
    }

    private func hasAnyInlineStyle(in targets: ResolvedCommandTargets) -> Bool {
        guard let inlineTarget = targets.inlineTarget else { return false }
        switch inlineTarget {
        case .caret:
            return !editorModel.storedMarks.isEmpty
        case .fragments(let fragments):
            return fragments.contains { fragment in
                editorModel.document.block(fragment.blockID)?.content.marks.contains {
                    $0.range.intersects(fragment.range)
                } ?? false
            }
        }
    }

    private func applyInlineStyle(
        _ style: BlockContent.InlineMark.Kind,
        to targets: ResolvedCommandTargets
    ) -> EditorUpdate? {
        guard let inlineTarget = targets.inlineTarget else { return nil }
        switch inlineTarget {
        case .caret:
            return handleCommand(.toggleStoredStyle(style))
        case .fragments(let fragments):
            let allCovered = fragments.allSatisfy { fragment in
                editorModel.document.block(fragment.blockID)?.content.coversEntirely(
                    style.caseIdentity,
                    in: fragment.range
                ) ?? false
            }
            let entries = fragments.compactMap { fragment -> EditorTransactionEntry? in
                guard let block = editorModel.document.block(fragment.blockID) else { return nil }
                if !allCovered,
                    block.content.coversEntirely(style.caseIdentity, in: fragment.range)
                {
                    return nil
                }
                return .command(
                    allCovered
                        ? .removeTextStyle(
                            blockID: fragment.blockID,
                            range: fragment.range,
                            style: style.caseIdentity
                        )
                        : .applyTextStyle(
                            blockID: fragment.blockID,
                            range: fragment.range,
                            style: style
                        )
                )
            }
            return handleTransaction(entries)
        }
    }

    private func clearInlineStyles(
        in targets: ResolvedCommandTargets
    ) -> EditorUpdate? {
        guard let inlineTarget = targets.inlineTarget else { return nil }
        switch inlineTarget {
        case .caret:
            guard !editorModel.storedMarks.isEmpty else { return nil }
            return handleCommand(.clearStoredStyles)
        case .fragments(let fragments):
            let entries = fragments.compactMap { fragment -> EditorTransactionEntry? in
                guard
                    editorModel.document.block(fragment.blockID)?.content.marks.contains(
                        where: { $0.range.intersects(fragment.range) }
                    ) == true
                else { return nil }
                return .command(
                    .clearTextStyles(blockID: fragment.blockID, range: fragment.range)
                )
            }
            return handleTransaction(entries)
        }
    }

    private func commandSelectionMode(
        for selection: EditorSelection
    ) -> EditorCommandSelectionMode {
        switch selection {
        case .inactive: .inactive
        case .caret: .caret
        case .text: .text
        case .blocks: .blocks
        }
    }

    private static let inlineStyleIdentities: [BlockContent.InlineMark.Kind.CaseIdentity] = [
        .strong, .emphasis, .code, .strikethrough, .link,
    ]

    private static let unavailableInlineStyles = Dictionary(
        uniqueKeysWithValues: inlineStyleIdentities.map { ($0, EditorToggleState.unavailable) }
    )
}

// MARK: - Command State Cache Identity

struct CommandStateCacheKey: Hashable {
    let committedDocumentRevision: EditorDocumentRevision
    let selectionIdentity: EditorSelectionIdentity
    let storedMarksIdentity: EditorStoredMarksIdentity
    let compositionIdentity: UInt64?
}
