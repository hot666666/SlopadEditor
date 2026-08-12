import SlopadCoreModel

// MARK: - EditorModelInputRuleOutcome

/// EditorModel's fixed rule composition. The slash signal is local runtime plumbing rather
/// than a CoreModel effect: only canonical format effects cross the core boundary.
enum EditorModelInputRuleOutcome {
    case canonical(EditorInputRuleEffect)
    case slashTrigger(triggerRange: TextRange)
}
