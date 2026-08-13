import Foundation
import SlopadEditorEngine

// MARK: - Snapshot Publication

/// The observable identity of one rendered surface.
///
/// Two snapshots that produce equal keys look identical to a host: same viewport, same
/// visible geometry and measurement requests, same selection, composition, history
/// availability, and drag chrome. Publishing both would notify the host twice for one
/// visible state.
///
/// This is a projection of Session facts and carries no AppKit state, but it lived inside
/// `AppKitEditorViewController`, where the deduplication rule could only be exercised
/// through a mounted window.
struct AppKitSnapshotPublicationKey: Equatable {
    struct VisibleBlock: Equatable {
        let markerKind: BlockMarkerKind
        let frame: EditorRect
        let textFrame: EditorRect
        let measureRequest: BlockMeasureRequest
    }

    struct ActiveTextInput: Equatable {
        let selectedRangeLowerBound: Int
        let selectedRangeUpperBound: Int
        let focusOffset: Int
        let focusAffinity: TextAffinity
        let navigationContext: TextNavigationContext?
        let measureRequest: BlockMeasureRequest
    }

    let viewport: EditorViewport
    let revision: EditorSnapshotRevision
    let totalHeight: Double
    let visibleBlocks: [VisibleBlock]
    let selection: EditorSelection
    let composition: TextComposition?
    let canUndo: Bool
    let canRedo: Bool
    let activeTextInput: ActiveTextInput?
    let dropIndicator: EditorRect?
    let blockSelectionRectangle: EditorRect?

    init(viewport: EditorViewport, snapshot: EditorSessionSnapshot) {
        self.viewport = viewport
        self.revision = snapshot.revision
        self.totalHeight = snapshot.totalHeight
        self.visibleBlocks = snapshot.visibleBlocks.map { block in
            VisibleBlock(
                markerKind: block.markerKind,
                frame: block.frame,
                textFrame: block.textRender.frame,
                measureRequest: block.textRender.measureRequest
            )
        }
        self.selection = snapshot.selection
        self.composition = snapshot.composition
        self.canUndo = snapshot.history.canUndo
        self.canRedo = snapshot.history.canRedo
        self.activeTextInput = snapshot.activeTextInput.map { activeTextInput in
            ActiveTextInput(
                selectedRangeLowerBound: activeTextInput.selectedRange.lowerBound,
                selectedRangeUpperBound: activeTextInput.selectedRange.upperBound,
                focusOffset: activeTextInput.focusOffset,
                focusAffinity: activeTextInput.focusAffinity,
                navigationContext: activeTextInput.navigationContext,
                measureRequest: activeTextInput.renderDescriptor.measureRequest
            )
        }
        self.dropIndicator = snapshot.blockDragState?.dropIndicator
        self.blockSelectionRectangle = snapshot.blockSelectionRectangleState?.rect
    }
}

/// Owns which surface the host was last told about, so one visible state produces one
/// notification.
///
/// The adapter still decides *when* to render; this decides whether the result is worth
/// telling the host about, and keeps the in-flight key visible to work that re-enters
/// during the callback.
@MainActor
final class AppKitSnapshotPublisher {
    private var activeKey: AppKitSnapshotPublicationKey?

    /// Whether `surface` is the publication currently being delivered.
    ///
    /// A caller that re-renders inside `onSnapshotChanged` observes the in-flight key, not
    /// the previous one, so it can recognize its own publication instead of treating it as
    /// a new surface.
    func isActivePublication(
        viewport: EditorViewport,
        snapshot: EditorSessionSnapshot
    ) -> Bool {
        guard let activeKey else { return false }
        return activeKey == AppKitSnapshotPublicationKey(viewport: viewport, snapshot: snapshot)
    }

    /// Delivers `snapshot` unless it is observably identical to the last published surface.
    ///
    /// The key is installed for the duration of `deliver` and then restored, rather than
    /// retained. Publication is a boundary event, not editor state: the adapter must be
    /// able to publish the same visible state again after something outside this key —
    /// native surface synchronization, for instance — has changed.
    func publish(
        _ snapshot: EditorSessionSnapshot,
        viewport: EditorViewport,
        deliver: (EditorSessionSnapshot) -> Void
    ) {
        let key = AppKitSnapshotPublicationKey(viewport: viewport, snapshot: snapshot)
        guard activeKey != key else { return }

        let previousKey = activeKey
        activeKey = key
        defer { activeKey = previousKey }
        deliver(snapshot)
    }
}
