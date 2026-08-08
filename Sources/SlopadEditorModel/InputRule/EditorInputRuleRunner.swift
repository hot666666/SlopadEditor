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

    package init(rules: [EditorInputRule]) {
        self.rules = rules
        triggers = rules.reduce(into: Set<Character>()) { $0.formUnion($1.triggers) }
    }

    /// The effect to apply, or `nil` when nothing matched.
    ///
    /// `committedText` is what was just inserted. Only its last character is consulted, so a
    /// multi-character insertion or replacement is evaluated once. IME commits reach this
    /// through `replaceText`; the separately classified paste command reaches it through
    /// `insertText` with the pasted string.
    package var maximumCandidateLookback: Int {
        // Reserve one grapheme for the right flank, so a matcher never inspects more than
        // its declared `scanLimit` even when syntax is completed mid-paragraph.
        max(0, (rules.map(\.scanLimit).max() ?? 0) - 1)
    }

    /// Whether an input can enter the bounded matcher path. Ordinary characters stop here
    /// before the model captures any String window.
    package func mayMatch(committedText: String) -> Bool {
        guard let closing = committedText.last else { return false }
        return triggers.contains(closing)
    }

    package func effect(
        committedText: String,
        candidate: EditorInputRuleCandidate
    ) -> EditorInputRuleEffect? {
        guard let closing = committedText.last, triggers.contains(closing) else { return nil }
        guard candidate.caretOffset > 0 else { return nil }

        for rule in rules where rule.triggers.contains(closing) {
            switch rule.scanOrigin {
            case .blockStart:
                guard candidate.baseOffset == 0,
                    candidate.caretOffset <= rule.scanLimit || rule.scanLimit == 0
                else { continue }
            case .caret:
                guard rule.scanLimit > 0 else { continue }
            }
            if let effect = rule.match(candidate) { return effect }
        }
        return nil
    }

}
