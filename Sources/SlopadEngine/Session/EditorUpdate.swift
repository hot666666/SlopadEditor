import SlopadCoreModel

// MARK: - EditorUpdate

public struct EditorUpdate: Sendable {
    public let selection: EditorSelection
    public let composition: TextComposition?
    public let history: EditorHistoryState
    /// Identifies the Session that produced this update.
    ///
    /// It rides alongside `committedDocumentRevision` so a host can capture both from the
    /// callback and later prove the pair still refers to the Session it came from. Without
    /// it the host has to keep its own generation counter and bump it on every Session
    /// replacement.
    public let epoch: EditorSessionEpoch
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
            epoch: EditorSessionEpoch,
            committedDocumentRevision: EditorDocumentRevision? = nil,
            layoutDirty: Bool,
            invalidation: EditorUpdateInvalidation
        ) {
            self.selection = selection
            self.previousSelection = previousSelection
            self.composition = composition
            self.history = history
            self.epoch = epoch
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
            epoch: EditorSessionEpoch,
            committedDocumentRevision: EditorDocumentRevision? = nil,
            invalidation: EditorUpdateInvalidation
        ) {
            self.selection = selection
            self.previousSelection = previousSelection
            self.composition = composition
            self.history = history
            self.epoch = epoch
            self.committedDocumentRevision = committedDocumentRevision
            self.invalidation = invalidation
        }
    #endif
}
