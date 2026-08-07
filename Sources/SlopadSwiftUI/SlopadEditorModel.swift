import Observation
import SlopadAppKit

// MARK: - SlopadEditorModel

/// The observable projection of one mounted editor.
///
/// `AppKitEditorViewController` publishes through single-assignment closures — one
/// `onUpdate`, one `onSnapshotChanged`. Independent host concerns (persistence, enabling an
/// undo button, showing a composing indicator) therefore have to be multiplexed through one
/// closure by whoever gets there first. This class does that multiplexing once and exposes
/// the results as observable properties, which is what a SwiftUI host wants anyway.
///
/// It deliberately holds no editing policy. Nothing here decides what a command means or
/// how selection moves; if that appears, the `EditorSession` boundary has regressed.
@Observable
@MainActor
public final class SlopadEditorModel {
    // MARK: - Observable State

    /// Identifies the mounted Session. It changes when the document is replaced.
    public private(set) var epoch: EditorSessionEpoch?
    /// The last committed document revision, or `nil` before the first commit.
    public private(set) var documentRevision: EditorDocumentRevision?
    public private(set) var canUndo = false
    public private(set) var canRedo = false
    /// Whether a native IME composition is in flight. Persisting during one loses the
    /// syllable being composed unless ``commitComposition()`` runs first.
    public private(set) var isComposing = false
    /// The settled document height, for a host sizing an inline editor.
    public private(set) var contentHeight: Double = 0

    /// The complete committed document, or `nil` before the editor is mounted.
    ///
    /// Reading this never throws and stays available during composition — but it reflects
    /// committed content, so a host that wants the in-flight syllable calls
    /// ``commitComposition()`` first.
    public var documentSnapshot: EditorDocumentSnapshot? {
        controller?.documentSnapshot
    }

    /// Whether the editor currently holds keyboard focus.
    public private(set) var isFocused = false

    // MARK: - Private State

    /// The mounted controller. `SlopadEditor` owns its lifetime; this is a back-reference.
    private weak var controller: AppKitEditorViewController?

    // MARK: - Init

    public init() {}

    // MARK: - Host Actions

    /// Commits any in-flight IME composition so the document includes it.
    ///
    /// Synchronous on purpose: a host calls this immediately before reading
    /// ``documentSnapshot`` to persist, and an asynchronous flush would let the read happen
    /// first and silently drop the last syllable.
    public func commitComposition() {
        _ = controller?.commitActiveComposition()
    }

    /// Gives the editor keyboard focus, or gives it up.
    public func setFocused(_ isFocused: Bool) {
        controller?.setFocused(isFocused)
    }

    /// Performs one editor action programmatically, for host toolbar buttons.
    @discardableResult
    public func perform(_ action: AppKitEditorAction) -> Bool {
        controller?.perform(action) != nil
    }

    // MARK: - Mounting

    /// Attaches a controller and seeds the observable state from it.
    func attach(_ controller: AppKitEditorViewController) {
        self.controller = controller
        epoch = controller.documentSnapshot.epoch
        contentHeight = controller.contentHeight
        isFocused = controller.isFocused
    }

    /// Detaches on unmount so a stale controller cannot be read back.
    func detach() {
        controller = nil
    }

    // MARK: - Controller Callbacks

    func apply(_ update: EditorUpdate) {
        epoch = update.epoch
        canUndo = update.history.canUndo
        canRedo = update.history.canRedo
        isComposing = update.composition != nil
        if let committed = update.committedDocumentRevision {
            documentRevision = committed
        }
    }

    func applyContentHeight(_ height: Double) {
        contentHeight = height
    }

    func applyFocus(_ isFocused: Bool) {
        self.isFocused = isFocused
    }

    /// Resets the per-Session state after the document was replaced.
    func applyDocumentReplacement(epoch: EditorSessionEpoch) {
        self.epoch = epoch
        documentRevision = nil
        canUndo = false
        canRedo = false
        isComposing = false
    }
}
