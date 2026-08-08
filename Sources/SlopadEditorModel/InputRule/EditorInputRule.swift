import SlopadCoreModel

// MARK: - EditorInputRuleEffect

/// What a matched rule wants done, as a value.
///
/// A rule decides; it does not mutate. That separation is what lets the runner put the whole
/// conversion in one transaction and roll the whole thing back when any part of it fails —
/// the previous implementation deleted the marker first and then changed the block kind, so
/// a failure in the second step left the marker gone.
package enum EditorInputRuleEffect: Equatable {
    /// Remove the marker text and become a different kind of block. `# ` → heading.
    case convertBlock(removing: TextRange, to: BlockKind)
}

// MARK: - EditorInputRule

/// A syntax the editor recognizes as it is typed.
///
/// `triggers` is the whole performance story. Markdown syntax always *closes* on a specific
/// character, so one set-membership test on the character just committed rejects ordinary
/// typing — every Hangul syllable, letter, and digit — before any scanning happens.
package struct EditorInputRule {
    /// Characters that can close this syntax.
    package let triggers: Set<Character>

    /// How far back from the caret this rule is willing to look, in graphemes.
    ///
    /// Bounded so a long paragraph costs no more than a short one, and so a rule can never
    /// walk out of the block it was typed in.
    package let scanLimit: Int

    /// Decides against the block's text and the caret. Returns `nil` for no match, which
    /// includes deliberate rejections — incomplete syntax stays literal text.
    package let match: @Sendable (_ text: String, _ caretOffset: Int) -> EditorInputRuleEffect?

    package init(
        triggers: Set<Character>,
        scanLimit: Int,
        match: @escaping @Sendable (_ text: String, _ caretOffset: Int) -> EditorInputRuleEffect?
    ) {
        self.triggers = triggers
        self.scanLimit = scanLimit
        self.match = match
    }
}
