import SlopadCoreModel

// MARK: - EditorSlashCommand

/// The fixed, document-oriented commands available from the `/` menu.
///
/// This is intentionally a closed vocabulary instead of a suggestion registry. A later
/// product requirement for another trigger can introduce its own contract without making
/// the first slash-only surface carry speculative extension points.
package enum EditorSlashCommand: CaseIterable, Hashable, Sendable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case bulletList
    case numberedList
    case quote
    case todo
    case codeBlock

    /// Short label used by the built-in AppKit overlay.
    package var title: String {
        switch self {
        case .paragraph: "Paragraph"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .bulletList: "Bulleted list"
        case .numberedList: "Numbered list"
        case .quote: "Quote"
        case .todo: "To-do"
        case .codeBlock: "Code block"
        }
    }

    /// Matches the label and a small set of command words, case-insensitively.
    package func matches(query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return searchTerms.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    var blockKind: BlockKind {
        switch self {
        case .paragraph: .paragraph
        case .heading1: .heading(level: .h1)
        case .heading2: .heading(level: .h2)
        case .heading3: .heading(level: .h3)
        case .bulletList: .unorderedListItem
        case .numberedList: .orderedListItem(restartNumber: nil)
        case .quote: .quote
        case .todo: .todo(isChecked: false)
        case .codeBlock: .codeBlock(language: nil)
        }
    }

    private var searchTerms: [String] {
        switch self {
        case .paragraph: [title, "text"]
        case .heading1: [title, "heading", "h1"]
        case .heading2: [title, "heading", "h2"]
        case .heading3: [title, "heading", "h3"]
        case .bulletList: [title, "bullet", "list"]
        case .numberedList: [title, "number", "list"]
        case .quote: [title, "blockquote"]
        case .todo: [title, "task", "checkbox"]
        case .codeBlock: [title, "code"]
        }
    }
}

// MARK: - EditorSlashCommandSource

/// An opaque compare-and-apply token for one projected slash-command context.
///
/// The AppKit adapter carries this value from presentation to selection without reading
/// its fields. Session creates and validates it because document identity, canonical
/// revision, selection, and slash-query meaning all belong behind the Session boundary.
package struct EditorSlashCommandSource: Hashable, Sendable {
    let sessionEpoch: EditorSessionEpoch
    let revision: EditorDocumentRevision
    let selection: EditorSelection
    let blockID: BlockID
    let triggerRange: TextRange
    let queryRange: TextRange
}

// MARK: - EditorSlashCommandPresentation

/// Noncanonical slash-query data projected with a rendered snapshot.
///
/// `source` is the opaque compare-and-apply token for choosing a command. The query itself
/// remains ordinary document text; this value is only Session runtime interpretation of it.
package struct EditorSlashCommandPresentation: Hashable, Sendable {
    package let blockID: BlockID
    package let triggerRange: TextRange
    package let queryRange: TextRange
    package let query: String
    package let source: EditorSlashCommandSource
    /// Caret geometry in document coordinates. It is absent when the active text block is
    /// outside this render snapshot, in which case a platform overlay must dismiss.
    package let anchor: EditorRect?
    package let commands: [EditorSlashCommand]

    init(
        blockID: BlockID,
        triggerRange: TextRange,
        queryRange: TextRange,
        query: String,
        source: EditorSlashCommandSource,
        anchor: EditorRect?,
        commands: [EditorSlashCommand]
    ) {
        self.blockID = blockID
        self.triggerRange = triggerRange
        self.queryRange = queryRange
        self.query = query
        self.source = source
        self.anchor = anchor
        self.commands = commands
    }
}
