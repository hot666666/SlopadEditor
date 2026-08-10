import SlopadCoreModel

// MARK: - Editor Command State

package enum EditorActionAvailability: Hashable, Sendable {
    case unavailable
    case available
    case availableAfterCompositionCommit
}

package enum EditorToggleState: Hashable, Sendable {
    case unavailable
    case off
    case on
    case mixed
}

package enum EditorMixedValue<Value: Hashable & Sendable>: Hashable, Sendable {
    case unavailable
    case value(Value)
    case mixed
}

package enum EditorCommandStateDetail: Hashable, Sendable {
    case lightweight
    case rich
}

package enum EditorCommandSelectionMode: Hashable, Sendable {
    case inactive
    case caret
    case text
    case blocks
}

/// Package-only semantic actions for built-in adapter chrome.
///
/// This is intentionally not a public host command surface. Native callbacks and the
/// existing public `EditorInputEvent` remain separate entry points, while both paths
/// converge on the same Session resolver and model transactions.
package enum EditorCommandAction: Hashable, Sendable {
    case toggleInlineStyle(BlockContent.InlineMark.Kind)
    case clearInlineStyles
    case setBlockKind(BlockKind)
    case indentBlocks
    case outdentBlocks
}

package struct EditorCommandState: Hashable, Sendable {
    package let selectionMode: EditorCommandSelectionMode
    package let detail: EditorCommandStateDetail
    package let inlineStyleAvailability: EditorActionAvailability
    package let clearInlineStylesAvailability: EditorActionAvailability
    package let inlineStyles: [BlockContent.InlineMark.Kind.CaseIdentity: EditorToggleState]
    package let blockKind: EditorMixedValue<BlockKind>
    package let indentBlocksAvailability: EditorActionAvailability
    package let outdentBlocksAvailability: EditorActionAvailability

    package func toggleState(
        for kind: BlockContent.InlineMark.Kind
    ) -> EditorToggleState {
        inlineStyles[kind.caseIdentity] ?? .unavailable
    }

    package func availability(for action: EditorCommandAction) -> EditorActionAvailability {
        switch action {
        case .toggleInlineStyle(let kind):
            return toggleState(for: kind) == .unavailable
                ? .unavailable
                : inlineStyleAvailability
        case .clearInlineStyles:
            return clearInlineStylesAvailability
        case .setBlockKind(let kind):
            switch blockKind {
            case .unavailable:
                return .unavailable
            case .value(let current) where current == kind:
                return .unavailable
            case .value, .mixed:
                return availabilityAdjustedForComposition(.available)
            }
        case .indentBlocks:
            return indentBlocksAvailability
        case .outdentBlocks:
            return outdentBlocksAvailability
        }
    }

    private func availabilityAdjustedForComposition(
        _ base: EditorActionAvailability
    ) -> EditorActionAvailability {
        guard base != .unavailable else { return .unavailable }
        return inlineStyleAvailability == .availableAfterCompositionCommit
            ? .availableAfterCompositionCommit
            : base
    }
}
