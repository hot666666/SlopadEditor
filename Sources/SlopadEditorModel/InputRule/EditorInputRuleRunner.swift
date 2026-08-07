import SlopadCoreModel

// MARK: - EditorInputRuleRunner

/// Decides whether anything typed just completed a recognized syntax.
///
/// Knows nothing about Markdown. The syntax lives in the rules it is given, so the format
/// layer can supply its own without this file changing.
package struct EditorInputRuleRunner {
    private let rules: [EditorInputRule]

    /// Union of every rule's triggers, computed once.
    ///
    /// This is the gate that keeps ordinary typing free: one `Set<Character>` lookup on the
    /// character just committed, and everything that is not a closing character stops here
    /// without touching the block's text.
    private let triggers: Set<Character>

    /// The furthest any rule will look back, so the scan window is bounded before any rule
    /// runs.
    private let scanLimit: Int

    package init(rules: [EditorInputRule]) {
        self.rules = rules
        triggers = rules.reduce(into: Set<Character>()) { $0.formUnion($1.triggers) }
        scanLimit = rules.map(\.scanLimit).max() ?? 0
    }

    /// The effect to apply, or `nil` when nothing matched.
    ///
    /// `committedText` is what was just inserted. Only its last character is consulted:
    /// pasted or programmatically inserted runs are not typing, and running rules over them
    /// would convert syntax the user never typed here.
    package func effect(
        committedText: String,
        in text: String,
        caretOffset: Int
    ) -> EditorInputRuleEffect? {
        guard let closing = committedText.last, triggers.contains(closing) else { return nil }
        guard caretOffset > 0, caretOffset <= text.count else { return nil }

        for rule in rules where rule.triggers.contains(closing) {
            guard caretOffset <= rule.scanLimit || rule.scanLimit == 0 else { continue }
            if let effect = rule.match(text, caretOffset) { return effect }
        }
        return nil
    }

    /// Whether this character can close anything at all.
    ///
    /// Exposed so a caller can skip building a candidate string for the overwhelmingly
    /// common case.
    package func isTrigger(_ character: Character) -> Bool {
        triggers.contains(character)
    }

    package var maximumScanLimit: Int { scanLimit }
}
