import Foundation
import SlopadBlockLayout
import SlopadCoreModel
import SlopadEditorModel

// MARK: - EditorSession

/// Mutable editor runtime owned and called serially by one executor.
///
/// `EditorSession` is intentionally not `Sendable`. A host keeps the session on the
/// executor where it was created and transfers only `Sendable` input, update, and snapshot
/// values across isolation boundaries.
public final class EditorSession {
    // MARK: - Public Interface

    public convenience init(
        blocks: [EditorBlockInput],
        selection: EditorSelection? = nil,
        textLayouter: any BlockTextLayoutProtocol
    ) {
        self.init(
            document: Document(blockInputs: blocks),
            selection: selection,
            textLayouter: textLayouter
        )
    }

    /// Returns the complete committed canonical document without viewport or live
    /// composition state.
    ///
    /// Unlike `documentContextSnapshot()` this never throws, so it stays readable while a
    /// native IME composition is in flight.
    public var documentSnapshot: EditorDocumentSnapshot {
        EditorDocumentSnapshot(
            epoch: sessionEpoch,
            revision: currentDocumentRevision,
            blocks: editorModel.document.editorBlockInputs
        )
    }

    // MARK: - State

    var editorModel: EditorModel
    var blockLayout: BlockLayout
    /// The whole seam, stored once.
    ///
    /// `private` so extensions in other files cannot reach it — they get the narrow views
    /// below instead. Two independently settable references would have to be kept in sync,
    /// and one assignment site updating only one of them is a silent divergence.
    private var textBackend: any BlockTextLayoutProtocol

    /// What Session itself asks about laid-out text.
    ///
    /// Excludes `BlockMeasuring` on purpose: measurement belongs to `BlockLayout`, behind
    /// its cache. Typing this view narrowly is what stops a later extension here from
    /// calling `measure` directly and bypassing that cache.
    var textLayouter: any TextGeometryResolving & TextNavigationResolving & TextDeletionResolving {
        textBackend
    }

    /// The measuring capability handed to `BlockLayout`, which is the only layer that measures.
    var blockMeasuring: any BlockMeasuring { textBackend }

    /// Swaps the stored value. Both views follow, because there is only one.
    ///
    /// Low-level: this does **not** advance the text-layout revision or invalidate cached
    /// measurements. A real runtime backend swap must go through
    /// `replaceTextLayoutBackend`, which ADR 0003 requires to do both. Reaching for this one
    /// directly would silently keep geometry from the previous backend.
    func replaceTextBackend(_ backend: any BlockTextLayoutProtocol) {
        textBackend = backend
        // `CaretGeometryKey` describes the request, not who answered it. A style swap can
        // change glyph metrics while text, width, depth, selection, and caret position all
        // stay identical, so the memo would keep serving rectangles measured in the previous
        // font. Nothing in the key can see that; only dropping it can.
        cachedCaretGeometry = nil
    }
    /// Last resolved caret/selection geometry, reused across surface convergence renders.
    var cachedCaretGeometry:
        (key: CaretGeometryKey, caretRect: EditorRect?, selectionRects: [EditorRect])?

    var composition: TextComposition?
    var compositionSelection: TextSelection?
    var blockDrag: (blockIDs: [BlockID], dropTarget: BlockDropTarget?, dropIndicator: EditorRect?)?
    var blockSelectionRectangle: (anchor: EditorPoint, current: EditorPoint)?
    var blockSelectionDragAnchor: BlockHitTestResult?
    var textSelectionDragAnchor: TextPosition?
    var textDoubleClickSelection: (blockID: BlockID, wordRange: TextRange)?
    var textNavigationRuntimeContext: EditorSessionTextNavigationRuntimeContext?
    /// Runtime interpretation of an ordinary leading `/query`; never canonical document
    /// state and never part of editor history.
    var slashCommandRuntime: SlashCommandRuntime?
    var pendingSlashCommandTrigger: (blockID: BlockID, triggerRange: TextRange)?
    private var compositionRevisionCounter: Int
    /// Identity of this Session instance. Serves both the persistence path
    /// (`EditorDocumentSnapshot`, `EditorUpdate`) and the patch CAS token
    /// (`EditorDocumentSource`).
    let sessionEpoch: EditorSessionEpoch
    private var documentChangeRevision: UInt64
    private var hasPendingDocumentChange: Bool
    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        var benchmarkMetrics: EditorSessionBenchmarkMetrics
    #endif

    // MARK: - Internal Initialization

    init(
        document: Document,
        selection: EditorSelection? = nil,
        textLayouter: any BlockTextLayoutProtocol
    ) {
        self.editorModel = EditorModel(document: document, selection: selection)
        self.blockLayout = BlockLayout()
        self.textBackend = textLayouter
        self.composition = nil
        self.compositionSelection = nil
        self.blockDrag = nil
        self.blockSelectionRectangle = nil
        self.blockSelectionDragAnchor = nil
        self.textSelectionDragAnchor = nil
        self.textDoubleClickSelection = nil
        self.textNavigationRuntimeContext = nil
        self.slashCommandRuntime = nil
        self.pendingSlashCommandTrigger = nil
        self.compositionRevisionCounter = 0
        self.sessionEpoch = EditorSessionEpoch()
        self.documentChangeRevision = 0
        self.hasPendingDocumentChange = false
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            self.benchmarkMetrics = EditorSessionBenchmarkMetrics()
        #endif
    }

    // MARK: - Internal State

    var historyState: EditorHistoryState {
        let availability = editorModel.historyAvailability
        return EditorHistoryState(
            canUndo: availability.canUndo,
            canRedo: availability.canRedo
        )
    }

    // MARK: - Composition Revision

    func nextTextComposition(
        blockID: BlockID,
        replacementRange: TextRange,
        text: String
    ) -> TextComposition {
        compositionRevisionCounter += 1
        return TextComposition(
            blockID: blockID,
            replacementRange: replacementRange,
            text: text,
            revision: compositionRevisionCounter
        )
    }

    func recordCompositionRevision(_ revision: Int) {
        compositionRevisionCounter = max(compositionRevisionCounter, revision)
    }

    // MARK: - Committed Document Change

    var currentDocumentRevision: EditorDocumentRevision {
        EditorDocumentRevision(rawValue: documentChangeRevision)
    }

    func recordDocumentChange() {
        hasPendingDocumentChange = true
    }

    func takePendingDocumentRevision() -> EditorDocumentRevision? {
        guard hasPendingDocumentChange else { return nil }
        precondition(
            documentChangeRevision < UInt64.max,
            "Editor document change revision exhausted"
        )
        documentChangeRevision += 1
        hasPendingDocumentChange = false
        return EditorDocumentRevision(rawValue: documentChangeRevision)
    }
}
