// MARK: - Editor Input Rule Contract

/// The canonical mutation selected by a typed-syntax matcher.
///
/// This is deliberately vocabulary, not an execution engine: a format target can describe
/// the canonical result without learning about history, selection routing, or transactions.
/// The editor-model runner performs those runtime responsibilities in one transaction.
package enum EditorInputRuleEffect: Equatable, Sendable {
    /// Remove a block marker and change the block kind. `# ` becomes a heading.
    case convertBlock(removing: TextRange, to: BlockKind)

    /// Remove source-only inline syntax and apply its canonical mark.
    ///
    /// Every range is expressed in the text *before* any removal. `marked` names the source
    /// content between delimiters; the runtime maps it after removing `removing`, preserving
    /// marks produced by an earlier nested conversion.
    case applyInline(
        marks: [BlockContent.InlineMark.Kind],
        removing: [TextRange],
        marked: TextRange
    )
}

/// A bounded text window captured at the same String indices used for the edit.
///
/// `baseOffset` keeps matching local while effects still name canonical grapheme offsets.
/// The optional one-character suffix lets delimiter logic inspect the right flank without
/// walking the rest of the block.
package struct EditorInputRuleCandidate: Sendable {
    package let text: String
    package let caretOffset: Int
    package let baseOffset: Int

    package init(
        text: String,
        caretOffset: Int,
        baseOffset: Int
    ) {
        self.text = text
        self.caretOffset = caretOffset
        self.baseOffset = baseOffset
    }
}

/// One bounded typed-syntax pattern.
///
/// The pattern data lives in a format-layer target. This core contract is shared only because
/// the format layer produces effects in canonical vocabulary and the editor model consumes
/// them atomically; it does not expose parser nodes or a generic plugin registry.
package struct EditorInputRule: Sendable {
    /// Where the bounded candidate begins. Block prefixes can only start at offset zero;
    /// inline syntax is a trailing local candidate at the caret.
    package enum ScanOrigin: Sendable {
        case blockStart
        case caret
    }

    /// Characters which may complete this syntax.
    package let triggers: Set<Character>

    /// Maximum number of graphemes examined by the matcher after a trigger fires.
    package let scanLimit: Int
    package let scanOrigin: ScanOrigin

    /// Returns `nil` when the bounded local candidate is not valid syntax.
    package let match: @Sendable (_ candidate: EditorInputRuleCandidate) -> EditorInputRuleEffect?

    package init(
        triggers: Set<Character>,
        scanLimit: Int,
        scanOrigin: ScanOrigin = .blockStart,
        match: @escaping @Sendable (_ candidate: EditorInputRuleCandidate) -> EditorInputRuleEffect?
    ) {
        self.triggers = triggers
        self.scanLimit = scanLimit
        self.scanOrigin = scanOrigin
        self.match = match
    }
}
