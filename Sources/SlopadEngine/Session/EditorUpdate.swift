import SlopadCoreModel

// MARK: - EditorUpdate

public struct EditorUpdate: Sendable {
    public let selection: EditorSelection
    public let composition: TextComposition?
    public let history: EditorHistoryState
    /// The Session-local document revision after a committed canonical mutation.
    ///
    /// This is `nil` for selection, layout, scrolling, and live IME composition updates.
    /// Read the owning Session's `documentSnapshot` synchronously when the complete value
    /// is needed.
    public let committedDocumentRevision: EditorDocumentRevision?

    // MARK: - Internal State

    let previousSelection: EditorSelection?
    #if SLOPAD_BENCHMARK_INSTRUMENTATION
    let layoutDirty: Bool
    #endif
    let invalidation: EditorUpdateInvalidation

    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        init(
            selection: EditorSelection,
            previousSelection: EditorSelection? = nil,
            composition: TextComposition? = nil,
            history: EditorHistoryState,
            committedDocumentRevision: EditorDocumentRevision? = nil,
            layoutDirty: Bool,
            invalidation: EditorUpdateInvalidation
        ) {
            self.selection = selection
            self.previousSelection = previousSelection
            self.composition = composition
            self.history = history
            self.committedDocumentRevision = committedDocumentRevision
            self.layoutDirty = layoutDirty
            self.invalidation = invalidation
        }
    #else
        init(
            selection: EditorSelection,
            previousSelection: EditorSelection? = nil,
            composition: TextComposition? = nil,
            history: EditorHistoryState,
            committedDocumentRevision: EditorDocumentRevision? = nil,
            invalidation: EditorUpdateInvalidation
        ) {
            self.selection = selection
            self.previousSelection = previousSelection
            self.composition = composition
            self.history = history
            self.committedDocumentRevision = committedDocumentRevision
            self.invalidation = invalidation
        }
    #endif
}
