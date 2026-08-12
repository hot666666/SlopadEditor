import SlopadEditorCoreModel

// MARK: - SlashCommandInputRule

/// The one concrete product input rule that starts the slash-command runtime.
///
/// It deliberately lives beside the fixed EditorModel rule composition rather than in the
/// Markdown target: `/` is product UI syntax, not Markdown. It matches only one concrete
/// leading slash candidate. It does not extend CoreModel's canonical input-rule vocabulary.
enum SlashCommandInputRule {
    static let maximumCandidateLookback = 1

    static func triggerRange(
        committedText: String,
        candidate: EditorInputRuleCandidate
    ) -> TextRange? {
        guard committedText == "/" else { return nil }
        guard
            candidate.baseOffset == 0,
            candidate.caretOffset == 1,
            candidate.text.first == "/"
        else {
            return nil
        }
        return TextRange(0, 1)
    }
}
