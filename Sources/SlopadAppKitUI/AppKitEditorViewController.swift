import AppKit
import Foundation
import SlopadAppKitTextKit
import SlopadEngine

// MARK: - AppKitEditorViewController

@MainActor
public final class AppKitEditorViewController: NSViewController {
    private enum UX {
        static let initialViewSize = NSSize(width: 920, height: 680)
        static let minimumViewportDimension: CGFloat = 1
        static let documentBottomPadding: CGFloat = 40
        static let selectionRevealPadding: CGFloat = 24
        static let scrollEpsilon: CGFloat = 0.5
        static let dropIndicatorHorizontalInset: CGFloat = 12
        static let blockSelectionFillAlpha: CGFloat = 0.18
        static let blockSelectionStrokeAlpha: CGFloat = 0.72
        static let blockSelectionStrokeInset: CGFloat = 0.5
        static let blockSelectionStrokeWidth: CGFloat = 1
        static let lineFragmentHitOutsetX: CGFloat = 4
        static let lineFragmentHitOutsetY: CGFloat = 3
        static let maximumSurfaceConvergencePassCount = 32
        static let maximumSurfaceFallbackPassCount = 4
        static let fallbackScrollableOverflow: CGFloat = 1
    }

    private struct SurfaceSyncRequest: Equatable {
        enum NativePolicy: Equatable {
            case synchronize
            case preserve
        }

        enum ViewportAction: Equatable {
            case none
            case revealSelection
            case scrollTo(Double)
        }

        var nativePolicy: NativePolicy
        var makeFirstResponder: Bool
        var viewportAction: ViewportAction
        var nativeStateIsAuthoritative: Bool

        static func synchronizeNative(
            makeFirstResponder: Bool,
            scrollSelectionIntoView: Bool
        ) -> Self {
            Self(
                nativePolicy: .synchronize,
                makeFirstResponder: makeFirstResponder,
                viewportAction: scrollSelectionIntoView ? .revealSelection : .none,
                nativeStateIsAuthoritative: false
            )
        }

        static func preserveNativeSurface(
            makeFirstResponder: Bool = false,
            scrollSelectionIntoView: Bool = false,
            scrollTargetY: Double? = nil,
            nativeStateIsAuthoritative: Bool = false
        ) -> Self {
            Self(
                nativePolicy: .preserve,
                makeFirstResponder: makeFirstResponder,
                viewportAction: scrollTargetY.map(ViewportAction.scrollTo)
                    ?? (scrollSelectionIntoView ? .revealSelection : .none),
                nativeStateIsAuthoritative: nativeStateIsAuthoritative
            )
        }

        mutating func merge(_ newerRequest: Self) {
            switch newerRequest.nativePolicy {
            case .synchronize:
                nativePolicy = .synchronize
                nativeStateIsAuthoritative = false
            case .preserve where nativePolicy == .preserve:
                nativeStateIsAuthoritative =
                    nativeStateIsAuthoritative || newerRequest.nativeStateIsAuthoritative
            case .preserve where newerRequest.nativeStateIsAuthoritative:
                nativePolicy = .preserve
                nativeStateIsAuthoritative = true
            case .preserve:
                break
            }
            makeFirstResponder = makeFirstResponder || newerRequest.makeFirstResponder
            if newerRequest.viewportAction != .none {
                viewportAction = newerRequest.viewportAction
            }
        }
    }

    private struct SnapshotVisibleBlockKey: Equatable {
        let markerKind: BlockMarkerKind
        let frame: EditorRect
        let textFrame: EditorRect
        let measureRequest: BlockMeasureRequest
    }

    private struct SnapshotActiveTextInputKey: Equatable {
        let selectedRangeLowerBound: Int
        let selectedRangeUpperBound: Int
        let focusOffset: Int
        let focusAffinity: TextAffinity
        let navigationContext: TextNavigationContext?
        let measureRequest: BlockMeasureRequest
    }

    private struct SnapshotPublicationKey: Equatable {
        let viewport: EditorViewport
        let revision: EditorSnapshotRevision
        let totalHeight: Double
        let visibleBlocks: [SnapshotVisibleBlockKey]
        let selection: EditorSelection
        let composition: TextComposition?
        let canUndo: Bool
        let canRedo: Bool
        let activeTextInput: SnapshotActiveTextInputKey?
        let dropIndicator: EditorRect?
        let blockSelectionRectangle: EditorRect?

        init(viewport: EditorViewport, snapshot: EditorSessionSnapshot) {
            self.viewport = viewport
            self.revision = snapshot.revision
            self.totalHeight = snapshot.totalHeight
            self.visibleBlocks = snapshot.visibleBlocks.map { block in
                SnapshotVisibleBlockKey(
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
                SnapshotActiveTextInputKey(
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

    // MARK: - Public State

    public var editorStyle: AppKitEditorStyle {
        textSystem.style
    }
    /// Complete committed canonical content, independent of the current viewport.
    /// `resetDocument` replaces the Session and starts this snapshot's revision at zero.
    public var documentSnapshot: EditorDocumentSnapshot {
        session.documentSnapshot
    }

    /// Captures the complete canonical document, exact selection, and selected content
    /// for a later compare-and-swap `applyDocumentPatch(_:)` call.
    ///
    /// Native marked text and Session composition must be committed before capture.
    public func documentContextSnapshot()
        throws(EditorDocumentTransactionError) -> EditorDocumentContextSnapshot
    {
        guard !hasActiveNativeMarkedText else {
            throw .activeComposition
        }
        return try session.documentContextSnapshot()
    }
    public private(set) var snapshot: EditorSessionSnapshot?
    public var blockChromeRenderer: any AppKitBlockChromeRenderer
    public var onSnapshotChanged: ((EditorSessionSnapshot) -> Void)?
    public var onUpdate: ((EditorUpdate) -> Void)?

    // MARK: - Package State

    package let scrollView = NSScrollView()
    package private(set) var session: EditorSession
    package var onDrawOverlay: ((NSRect, EditorSessionSnapshot) -> Void)?
    package var onDrawCompleted: ((NSRect, UInt64) -> Void)?

    var canvasView: AppKitEditorCanvasView {
        editorCanvasView
    }

    // MARK: - Private State

    private var textSystem: AppKitTextSystem
    private var textLayouter: TextKitBlockTextLayouter {
        textSystem.textLayouter
    }
    private var textRenderer: TextKitBlockRenderer {
        textSystem.textRenderer
    }
    private var textInputDecorationRenderer: AppKitTextInputDecorationRenderer {
        textSystem.textInputDecorationRenderer
    }
    private lazy var editorCanvasView = AppKitEditorCanvasView(handler: self)
    private lazy var activeInputController = AppKitActiveInputController(owner: self)
    private lazy var dragAutoscrollController = AppKitDragAutoscrollController(
        visibleBounds: { [weak self] in
            self?.currentViewportBounds() ?? .zero
        },
        documentHeight: { [weak self] in
            self?.editorCanvasView.frame.height ?? 0
        },
        scrollToY: { [weak self] targetY in
            self?.scrollDocumentForDragAutoscroll(to: targetY)
        },
        applyDragUpdate: { [weak self] kind, documentPoint in
            self?.applyDragUpdate(kind: kind, documentPoint: documentPoint) ?? false
        }
    )
    private var isAdjustingScrollPosition = false
    private var isSynchronizingSurface = false
    private var pendingSurfaceSyncRequest: SurfaceSyncRequest?
    private var activeSnapshotPublicationKey: SnapshotPublicationKey?
    private let focusOnAppear: Bool

    // MARK: - Init

    public init(
        blocks: [EditorBlockInput],
        selection: EditorSelection? = nil,
        style: AppKitEditorStyle = AppKitEditorStyle(),
        blockChromeRenderer: any AppKitBlockChromeRenderer = AppKitDefaultBlockChromeRenderer(),
        focusOnAppear: Bool = false
    ) {
        let textSystem = AppKitTextSystem(style: style)
        self.textSystem = textSystem
        self.session = EditorSession(
            blocks: blocks,
            selection: selection,
            textLayouter: textSystem.textLayouter
        )
        self.blockChromeRenderer = blockChromeRenderer
        self.focusOnAppear = focusOnAppear
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    public override func loadView() {
        view = makeRootView()
        setupScrollView()
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        renderAndSyncSurface(makeFirstResponder: hasActiveTextInput)
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        if focusOnAppear {
            renderAndSyncSurface(makeFirstResponder: true)
        }
    }

    // MARK: - Public Actions

    public func renderAndSyncSurface(
        makeFirstResponder: Bool,
        scrollSelectionIntoView: Bool = false
    ) {
        requestSurfaceSync(
            .synchronizeNative(
                makeFirstResponder: makeFirstResponder,
                scrollSelectionIntoView: scrollSelectionIntoView
            )
        )
    }

    public func focus(blockID: BlockID, offset: Int) {
        handleNativeInputEvent(
            .activeTextSelectionChanged(
                blockID: blockID,
                selectedRange: .point(offset)
            )
        )
        renderAndSyncSurface(makeFirstResponder: true, scrollSelectionIntoView: true)
    }

    /// Replaces the adapter-owned TextKit layout and drawing pipeline from one style.
    ///
    /// The operation synchronizes the Session snapshot and canvas before returning while
    /// preserving live marked text, native selection, viewport, and responder ownership.
    public func updateEditorStyle(_ style: AppKitEditorStyle) {
        guard style != editorStyle else { return }

        let replacementTextSystem = AppKitTextSystem(style: style)
        _ = session.replaceTextLayoutBackend(with: replacementTextSystem.textLayouter)
        textSystem = replacementTextSystem
        renderCanvasPreservingNativeSurface(
            nativeStateIsAuthoritative: hasActiveNativeMarkedText
        )
    }

    public func resetDocument(
        blocks: [EditorBlockInput],
        selection: EditorSelection? = nil
    ) {
        let shouldKeepFirstResponder = view.window?.firstResponder === editorCanvasView
        resetDocumentWithoutRendering(blocks: blocks, selection: selection)
        renderAndSyncSurface(
            makeFirstResponder: shouldKeepFirstResponder,
            scrollSelectionIntoView: true
        )
    }

    package func resetDocumentWithoutRendering(
        blocks: [EditorBlockInput],
        selection: EditorSelection? = nil
    ) {
        dragAutoscrollController.stop()
        session = EditorSession(
            blocks: blocks,
            selection: selection,
            textLayouter: textLayouter
        )
        snapshot = nil
        activeInputController.hide()
    }

    @discardableResult
    package func handleInputWithoutRendering(_ inputEvent: EditorInputEvent) -> EditorUpdate? {
        handleNativeInputEvent(inputEvent)
    }

    public func replaceActiveText(
        _ text: String,
        preservingNativeSelection: Bool = false,
        blockID explicitBlockID: BlockID? = nil
    ) {
        guard
            let blockID = explicitBlockID ?? currentActiveTextBlockID(),
            snapshotText(for: blockID) != nil
        else { return }

        activeInputController.replaceText(
            text,
            blockID: blockID,
            preservingNativeSelection: preservingNativeSelection
        )
    }

    /// Performs one programmatic editor action and synchronizes the native surface before
    /// returning. Viewport-bearing engine commands use the adapter's current viewport.
    @discardableResult
    public func perform(
        _ action: AppKitEditorAction,
        makeFirstResponder: Bool = true,
        scrollSelectionIntoView: Bool = true
    ) -> EditorUpdate? {
        _ = commitActiveComposition()
        return handleInput(
            action.inputEvent(viewport: currentViewport()),
            makeFirstResponder: makeFirstResponder,
            scrollSelectionIntoView: scrollSelectionIntoView
        )
    }

    /// Applies one canonical full-document post-image and synchronizes the AppKit surface.
    ///
    /// The source must still match the controller's Session instance, committed document
    /// revision, and exact selection. A successful mutation publishes exactly one
    /// `onUpdate` callback before this method returns. An exact semantic no-op publishes
    /// no callback and returns `nil`.
    @discardableResult
    public func applyDocumentPatch(
        _ patch: EditorDocumentPatch
    ) throws(EditorDocumentTransactionError) -> EditorUpdate? {
        guard !hasActiveNativeMarkedText else {
            throw .activeComposition
        }
        guard let update = try session.applyDocumentPatch(patch) else { return nil }

        onUpdate?(update)
        let shouldKeepFirstResponder = view.window?.firstResponder === editorCanvasView
        renderAndSyncSurface(
            makeFirstResponder: shouldKeepFirstResponder,
            scrollSelectionIntoView: true
        )
        return update
    }

    /// Commits live marked text while preserving viewport and responder ownership.
    ///
    /// The committed update is delivered to `onUpdate` before this method returns, so the
    /// matching complete value can be read immediately from `documentSnapshot`.
    @discardableResult
    public func commitActiveComposition() -> EditorUpdate? {
        guard hasActiveNativeMarkedText || snapshot?.composition != nil else { return nil }
        let shouldKeepFirstResponder = view.window?.firstResponder === editorCanvasView
        return handleInput(
            .commitComposition,
            makeFirstResponder: shouldKeepFirstResponder,
            scrollSelectionIntoView: false
        )
    }

    @discardableResult
    package func handleInput(
        _ inputEvent: EditorInputEvent,
        makeFirstResponder: Bool = true,
        scrollSelectionIntoView: Bool = true
    ) -> EditorUpdate? {
        guard let update = handleNativeInputEvent(inputEvent) else { return nil }
        renderAndSyncSurface(
            makeFirstResponder: makeFirstResponder,
            scrollSelectionIntoView: scrollSelectionIntoView
        )
        return update
    }

    package func renderPreservingNativeSurface() {
        renderCanvasPreservingNativeSurface(nativeStateIsAuthoritative: true)
    }

    public func scrollDocument(to y: Double) {
        renderCanvasPreservingNativeSurface(
            scrollTargetY: max(0, y),
            nativeStateIsAuthoritative: hasActiveNativeMarkedText
        )
    }

    package func scrollDocumentWithoutRendering(to y: Double) {
        scrollDocument(to: CGFloat(max(0, y)), visibleBounds: currentViewportBounds())
    }

    package func currentViewport() -> EditorViewport {
        let bounds = currentViewportBounds()
        let width = max(Double(bounds.width), Double(UX.minimumViewportDimension))
        let height = max(Double(bounds.height), Double(UX.minimumViewportDimension))
        return EditorViewport(
            width: width,
            scrollY: max(0, Double(bounds.origin.y)),
            height: height
        )
    }

    package var activeNativeText: String {
        activeInputController.activeText
    }

    package var activeNativeSelectedRange: NSRange {
        activeInputController.activeSelectedRange
    }

    var activeNativeMarkedRange: NSRange {
        activeInputController.activeMarkedRange
    }

    package var hasActiveNativeMarkedText: Bool {
        activeInputController.hasMarkedText
    }

    package func hideActiveNativeSurface() {
        activeInputController.hide()
    }

    // MARK: - Setup

    private func makeRootView() -> NSView {
        let rootView = NSView(
            frame: NSRect(
                origin: .zero,
                size: UX.initialViewSize
            )
        )
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        return rootView
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = editorCanvasView
        view.addSubview(scrollView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewContentBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func scrollViewContentBoundsDidChange(_ notification: Notification) {
        guard !isAdjustingScrollPosition, !isSynchronizingSurface else { return }
        if hasActiveNativeMarkedText {
            renderCanvasPreservingNativeSurface(nativeStateIsAuthoritative: true)
        } else {
            renderAndSyncSurface(makeFirstResponder: hasActiveTextInput)
        }
    }

    private func currentViewportBounds() -> CGRect {
        var bounds = scrollView.contentView.bounds
        let fallback = view.bounds
        if bounds.width <= UX.minimumViewportDimension,
            fallback.width > UX.minimumViewportDimension
        {
            bounds.size.width = fallback.width
        }
        if bounds.height <= UX.minimumViewportDimension,
            fallback.height > UX.minimumViewportDimension
        {
            bounds.size.height = fallback.height
        }
        return bounds
    }

    private func resizeCanvas(for snapshot: EditorSessionSnapshot) {
        editorCanvasView.setFrameSize(canvasSize(for: snapshot))
    }

    private func canvasSize(for snapshot: EditorSessionSnapshot) -> NSSize {
        let bounds = currentViewportBounds()
        let documentHeight = max(
            CGFloat(snapshot.totalHeight) + UX.documentBottomPadding,
            bounds.height
        )
        return NSSize(
            width: max(UX.minimumViewportDimension, bounds.width),
            height: documentHeight
        )
    }

    private func invalidateVisibleCanvas() {
        editorCanvasView.setNeedsDisplay(scrollView.contentView.bounds)
    }

    private func renderCanvasPreservingNativeSurface(
        makeFirstResponder: Bool = false,
        scrollSelectionIntoView: Bool = false,
        scrollTargetY: Double? = nil,
        nativeStateIsAuthoritative: Bool = false
    ) {
        requestSurfaceSync(
            .preserveNativeSurface(
                makeFirstResponder: makeFirstResponder,
                scrollSelectionIntoView: scrollSelectionIntoView,
                scrollTargetY: scrollTargetY,
                nativeStateIsAuthoritative: nativeStateIsAuthoritative
            )
        )
    }

    private func requestSurfaceSync(_ request: SurfaceSyncRequest) {
        if isSynchronizingSurface {
            enqueueSurfaceSyncRequest(request)
            return
        }

        isSynchronizingSurface = true
        var nextRequest: SurfaceSyncRequest? = request
        var finalViewport: EditorViewport?
        var finalSnapshot: EditorSessionSnapshot?
        var convergencePassCount = 0

        while let currentRequest = nextRequest {
            pendingSurfaceSyncRequest = nil
            let renderedSurface = performSurfaceSync(currentRequest)
            finalViewport = renderedSurface.viewport
            finalSnapshot = renderedSurface.snapshot
            convergencePassCount += 1

            if convergencePassCount >= UX.maximumSurfaceConvergencePassCount,
                var fallbackRequest = pendingSurfaceSyncRequest
            {
                fallbackRequest.makeFirstResponder = false
                pendingSurfaceSyncRequest = nil
                let fallbackSurface = performSurfaceSync(fallbackRequest)
                finalViewport = fallbackSurface.viewport
                finalSnapshot = fallbackSurface.snapshot
                pendingSurfaceSyncRequest = nil
                break
            }
            nextRequest = pendingSurfaceSyncRequest
        }

        isSynchronizingSurface = false
        if let finalViewport, let finalSnapshot {
            publishSnapshot(finalSnapshot, viewport: finalViewport)
        }
    }

    private func enqueueSurfaceSyncRequest(_ request: SurfaceSyncRequest) {
        guard var pendingSurfaceSyncRequest else {
            self.pendingSurfaceSyncRequest = request
            return
        }
        pendingSurfaceSyncRequest.merge(request)
        self.pendingSurfaceSyncRequest = pendingSurfaceSyncRequest
    }

    private func performSurfaceSync(
        _ request: SurfaceSyncRequest
    ) -> (viewport: EditorViewport, snapshot: EditorSessionSnapshot) {
        var renderedSurface = renderAndResizeCanvas()

        switch request.viewportAction {
        case .scrollTo(let scrollTargetY):
            for _ in 0..<UX.maximumSurfaceConvergencePassCount {
                scrollDocument(
                    to: CGFloat(scrollTargetY),
                    visibleBounds: currentViewportBounds()
                )
                guard currentViewport() != renderedSurface.viewport else { break }
                renderedSurface = renderAndResizeCanvas()
            }

        case .revealSelection:
            scrollActiveSelectionIntoView(viewport: renderedSurface.viewport)
            if currentViewport() != renderedSurface.viewport {
                renderedSurface = renderAndResizeCanvas()
            }

        case .none:
            break
        }

        let isReentrantDuplicate = isActiveSnapshotPublication(renderedSurface)
        let shouldSyncPreservedNativeSurface =
            !request.nativeStateIsAuthoritative
            && nativeSurfaceNeedsSynchronization(renderedSurface.snapshot)
        switch request.nativePolicy {
        case .synchronize where !isReentrantDuplicate:
            syncNativeSurface(
                snapshot: renderedSurface.snapshot,
                makeFirstResponder: request.makeFirstResponder
            )
        case .preserve where shouldSyncPreservedNativeSurface:
            syncNativeSurface(
                snapshot: renderedSurface.snapshot,
                makeFirstResponder: request.makeFirstResponder
            )
        case .synchronize, .preserve:
            focusNativeSurfaceIfRequested(
                snapshot: renderedSurface.snapshot,
                makeFirstResponder: request.makeFirstResponder
            )
        }

        invalidateVisibleCanvas()
        return renderedSurface
    }

    private func isActiveSnapshotPublication(
        _ renderedSurface: (viewport: EditorViewport, snapshot: EditorSessionSnapshot)
    ) -> Bool {
        guard let activeSnapshotPublicationKey else { return false }
        let isSameSnapshot = activeSnapshotPublicationKey
            == SnapshotPublicationKey(
                viewport: renderedSurface.viewport,
                snapshot: renderedSurface.snapshot
            )
        return isSameSnapshot && nativeSurfaceMatches(renderedSurface.snapshot)
    }

    private func nativeSurfaceNeedsSynchronization(_ snapshot: EditorSessionSnapshot) -> Bool {
        snapshot.activeTextInput != nil && !nativeSurfaceMatches(snapshot)
    }

    private func nativeSurfaceMatches(_ snapshot: EditorSessionSnapshot) -> Bool {
        guard let activeTextInput = snapshot.activeTextInput else {
            return activeInputController.activeBlockID == nil
        }

        let request = activeTextInput.renderDescriptor.measureRequest
        guard
            activeInputController.activeBlockID == request.blockID,
            activeInputController.activeText == request.text
        else { return false }

        if activeInputController.hasMarkedText {
            return snapshot.composition != nil
        }
        return activeInputController.activeSelectedRange
            == activeTextInput.selectedRange.textKitNSRange(in: request.text)
    }

    private func publishSnapshot(
        _ snapshot: EditorSessionSnapshot,
        viewport: EditorViewport
    ) {
        guard let onSnapshotChanged else { return }
        let publicationKey = SnapshotPublicationKey(viewport: viewport, snapshot: snapshot)
        guard activeSnapshotPublicationKey != publicationKey else { return }

        let previousPublicationKey = activeSnapshotPublicationKey
        activeSnapshotPublicationKey = publicationKey
        defer { activeSnapshotPublicationKey = previousPublicationKey }
        onSnapshotChanged(snapshot)
    }

    private func renderAndResizeCanvas() -> (
        viewport: EditorViewport,
        snapshot: EditorSessionSnapshot
    ) {
        var viewport = currentViewport()
        for _ in 0..<UX.maximumSurfaceConvergencePassCount {
            let nextSnapshot = session.render(in: viewport)
            snapshot = nextSnapshot
            resizeCanvas(for: nextSnapshot)

            let adjustedViewport = currentViewport()
            guard adjustedViewport != viewport else {
                return (viewport, nextSnapshot)
            }
            viewport = adjustedViewport
        }
        return renderSurfaceFallback()
    }

    private func renderSurfaceFallback() -> (
        viewport: EditorViewport,
        snapshot: EditorSessionSnapshot
    ) {
        scrollDocument(to: 0, visibleBounds: currentViewportBounds())
        var viewport = currentViewport()
        var minimumCanvasHeight = max(
            UX.minimumViewportDimension,
            currentViewportBounds().height + UX.fallbackScrollableOverflow
        )

        for _ in 0..<UX.maximumSurfaceFallbackPassCount {
            let nextSnapshot = session.render(in: viewport)
            snapshot = nextSnapshot
            var nextCanvasSize = canvasSize(for: nextSnapshot)
            minimumCanvasHeight = max(minimumCanvasHeight, nextCanvasSize.height)
            nextCanvasSize.height = minimumCanvasHeight
            editorCanvasView.setFrameSize(nextCanvasSize)
            scrollView.tile()
            scrollDocument(to: 0, visibleBounds: currentViewportBounds())

            let adjustedViewport = currentViewport()
            guard adjustedViewport != viewport else {
                return (viewport, nextSnapshot)
            }
            viewport = adjustedViewport
        }

        return renderSurfaceWithPersistentVerticalScroller()
    }

    private func renderSurfaceWithPersistentVerticalScroller() -> (
        viewport: EditorViewport,
        snapshot: EditorSessionSnapshot
    ) {
        scrollView.autohidesScrollers = false
        scrollView.tile()
        scrollDocument(to: 0, visibleBounds: currentViewportBounds())

        let viewport = currentViewport()
        let nextSnapshot = session.render(in: viewport)
        snapshot = nextSnapshot
        resizeCanvas(for: nextSnapshot)
        scrollView.tile()
        scrollDocument(to: 0, visibleBounds: currentViewportBounds())

        let adjustedViewport = currentViewport()
        guard adjustedViewport != viewport else {
            return (viewport, nextSnapshot)
        }

        let adjustedSnapshot = session.render(in: adjustedViewport)
        snapshot = adjustedSnapshot
        resizeCanvas(for: adjustedSnapshot)
        scrollView.tile()
        scrollDocument(to: 0, visibleBounds: currentViewportBounds())
        precondition(
            currentViewport() == adjustedViewport,
            "A persistent vertical scroller must stabilize the editor viewport"
        )
        return (adjustedViewport, adjustedSnapshot)
    }

    private func syncNativeSurface(snapshot: EditorSessionSnapshot, makeFirstResponder: Bool) {
        activeInputController.sync(activeTextInput: snapshot.activeTextInput)
        focusNativeSurfaceIfRequested(
            snapshot: snapshot,
            makeFirstResponder: makeFirstResponder
        )
    }

    private func focusNativeSurfaceIfRequested(
        snapshot: EditorSessionSnapshot,
        makeFirstResponder: Bool
    ) {
        guard makeFirstResponder, snapshot.activeTextInput != nil else { return }
        view.window?.makeFirstResponder(editorCanvasView)
    }

    private func scrollActiveSelectionIntoView(viewport: EditorViewport) {
        guard
            let activePosition = activeTextPosition(),
            let frame = session.blockRevealFrame(for: activePosition.blockID, viewport: viewport)
        else { return }

        let visibleBounds = currentViewportBounds()
        let blockMinY = CGFloat(frame.y)
        let blockMaxY = CGFloat(frame.y + frame.height)
        var targetY = visibleBounds.origin.y

        if blockMaxY + UX.selectionRevealPadding > visibleBounds.maxY {
            targetY = blockMaxY + UX.selectionRevealPadding - visibleBounds.height
        }
        if blockMinY - UX.selectionRevealPadding < targetY {
            targetY = blockMinY - UX.selectionRevealPadding
        }

        let maxY = max(0, editorCanvasView.frame.height - visibleBounds.height)
        targetY = min(max(0, targetY), maxY)
        guard abs(targetY - visibleBounds.origin.y) > UX.scrollEpsilon else { return }

        scrollDocument(to: targetY, visibleBounds: visibleBounds)
    }

    private func scrollDocumentForDragAutoscroll(to targetY: CGFloat) {
        scrollDocument(to: targetY, visibleBounds: currentViewportBounds())
    }

    private func scrollDocument(to targetY: CGFloat, visibleBounds: CGRect) {
        let maximumY = max(0, editorCanvasView.frame.height - visibleBounds.height)
        let clampedTargetY = min(max(0, targetY), maximumY)
        isAdjustingScrollPosition = true
        defer { isAdjustingScrollPosition = false }
        scrollView.contentView.scroll(
            to: NSPoint(x: visibleBounds.origin.x, y: clampedTargetY)
        )
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

// MARK: - Canvas Handling

extension AppKitEditorViewController: AppKitEditorCanvasHandler {
    // MARK: - Drawing

    func drawCanvas(_ dirtyRect: NSRect) {
        let drawStart = DispatchTime.now().uptimeNanoseconds
        defer {
            onDrawCompleted?(
                dirtyRect,
                DispatchTime.now().uptimeNanoseconds - drawStart
            )
        }

        guard let snapshot else { return }
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        let selectedBlockIDs = selectedBlockIDs(in: snapshot)
        let activeTextBlockID = snapshot.activeTextInput?.renderDescriptor.measureRequest.blockID
        for rendered in snapshot.visibleBlocks {
            let isActive = rendered.id == activeTextBlockID
            let blockFrame = CGRect(editorRect: rendered.frame)
            do {
                cgContext.saveGState()
                defer { cgContext.restoreGState() }
                cgContext.clip(to: blockFrame)
                blockChromeRenderer.drawChrome(
                    AppKitBlockChromeRenderContext(
                        blockID: rendered.id,
                        kind: rendered.kind,
                        markerKind: rendered.markerKind,
                        depth: rendered.depth,
                        blockFrame: blockFrame,
                        style: editorStyle,
                        graphicsContext: cgContext,
                        isActive: isActive,
                        isSelected: selectedBlockIDs.contains(rendered.id)
                    )
                )
            }
        }

        for rendered in snapshot.visibleBlocks {
            textRenderer.draw(rendered.textRender, context: cgContext)
        }
        if let activeTextInput = snapshot.activeTextInput {
            textInputDecorationRenderer.draw(
                activeTextInput,
                graphicsContext: cgContext
            )
        }
        drawBlockSelectionRectangle(snapshot.blockSelectionRectangleState?.rect)
        drawDropIndicator(snapshot.blockDragState?.dropIndicator)
        onDrawOverlay?(dirtyRect, snapshot)
    }

    // MARK: - Mouse Events

    package func handleMouseDown(documentPoint: CGPoint, clickCount: Int) {
        dragAutoscrollController.stop()
        if clickCount >= 2 {
            handleMouseDoubleClick(documentPoint: documentPoint)
        } else {
            handleMouseDown(documentPoint: documentPoint)
        }
    }

    package func handleMouseDragged(documentPoint: CGPoint) {
        if snapshot?.blockDragState != nil {
            guard applyDragUpdate(kind: .blockDrag, documentPoint: documentPoint) else { return }
            dragAutoscrollController.update(kind: .blockDrag, documentPoint: documentPoint)
            return
        }

        if snapshot?.blockSelectionRectangleState != nil {
            guard applyDragUpdate(kind: .blockSelectionRectangle, documentPoint: documentPoint)
            else { return }
            dragAutoscrollController.update(
                kind: .blockSelectionRectangle,
                documentPoint: documentPoint
            )
            return
        }

        let viewport = currentViewport()
        let point = EditorPoint(x: Double(documentPoint.x), y: Double(documentPoint.y))
        if let update = session.handleInput(
            .pointer(
                .updateTextSelection(
                    documentPoint: point,
                    viewport: viewport,
                    blockSelectionThreshold: textDragBlockSelectionThreshold
                )
            )
        ) {
            onUpdate?(update)
            if case .blocks = update.selection {
                activeInputController.hide()
                renderAndSyncSurface(makeFirstResponder: false)
            } else {
                renderAndSyncSurface(makeFirstResponder: true)
            }
            return
        }

        guard case .blocks = snapshot?.selection else { return }
        guard applyDragUpdate(kind: .blockSelectionExtension, documentPoint: documentPoint)
        else { return }
        dragAutoscrollController.update(
            kind: .blockSelectionExtension,
            documentPoint: documentPoint
        )
    }

    package func handleMouseUp(documentPoint: CGPoint) {
        dragAutoscrollController.stop()
        let viewport = currentViewport()
        let point = EditorPoint(x: Double(documentPoint.x), y: Double(documentPoint.y))
        if snapshot?.blockDragState != nil {
            handleNativeInputEvent(.pointer(.endBlockDrag(documentPoint: point, viewport: viewport)))
            renderAndSyncSurface(makeFirstResponder: false)
        } else if snapshot?.blockSelectionRectangleState != nil {
            handleNativeInputEvent(.pointer(.endBlockSelectionRectangle))
            renderAndSyncSurface(makeFirstResponder: false)
        } else {
            handleNativeInputEvent(.pointer(.endTextSelection))
            handleNativeInputEvent(.pointer(.endBlockSelection))
        }
    }

    // MARK: - Native Commands

    package func handleNativeCommand(_ commandSelector: Selector) -> Bool {
        activeInputController.handleCommand(commandSelector)
    }

    // MARK: - Native Text Surface

    package func insertTextFromNativeSurface(_ text: String, replacementRange: NSRange) {
        activeInputController.insertText(text, replacementRange: replacementRange)
    }

    package func setMarkedTextFromNativeSurface(
        _ text: String,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        activeInputController.setMarkedText(
            text,
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
    }

    package func unmarkTextFromNativeSurface() {
        activeInputController.unmarkText()
    }

    func nativeSelectedRange() -> NSRange {
        activeInputController.activeSelectedRange
    }

    func nativeMarkedRange() -> NSRange {
        activeInputController.activeMarkedRange
    }

    func hasMarkedTextForNativeSurface() -> Bool {
        activeInputController.hasMarkedText
    }

    func attributedSubstringForNativeSurface(range: NSRange) -> NSAttributedString? {
        let text = activeInputController.activeText
        guard let swiftRange = Range(range, in: text) else { return nil }
        return NSAttributedString(string: String(text[swiftRange]))
    }

    func firstRectForNativeSurface(range: NSRange) -> NSRect {
        guard
            let activeTextInput = snapshot?.activeTextInput,
            let caretRect = caretRect(for: activeTextInput)
        else { return .zero }
        let windowRect = editorCanvasView.convert(caretRect, to: nil)
        return view.window?.convertToScreen(windowRect) ?? windowRect
    }
}

// MARK: - Native Input Owner

extension AppKitEditorViewController: AppKitActiveInputOwner {
    func documentTextForNativeInput(blockID: BlockID) -> String? {
        snapshotText(for: blockID)
    }

    func selectedPlainTextForClipboard() -> String? {
        session.selectedPlainText()
    }

    @discardableResult
    func handleNativeInputEvent(_ inputEvent: EditorInputEvent) -> EditorUpdate? {
        guard let update = session.handleInput(inputEvent) else { return nil }
        onUpdate?(update)
        return update
    }

    func handleActiveInputRenderRequest(_ request: AppKitActiveInputRenderRequest) {
        if request.preserveNativeSurface {
            renderCanvasPreservingNativeSurface(
                makeFirstResponder: request.makeFirstResponder,
                scrollSelectionIntoView: request.scrollSelectionIntoView,
                nativeStateIsAuthoritative: true
            )
        } else {
            renderAndSyncSurface(
                makeFirstResponder: request.makeFirstResponder,
                scrollSelectionIntoView: request.scrollSelectionIntoView
            )
        }
    }
}

// MARK: - Pointer Handling

extension AppKitEditorViewController {
    @discardableResult
    private func applyDragUpdate(
        kind: AppKitDragAutoscrollKind,
        documentPoint: CGPoint
    ) -> Bool {
        let viewport = currentViewport()
        let point = EditorPoint(x: Double(documentPoint.x), y: Double(documentPoint.y))
        let update: EditorUpdate?

        switch kind {
        case .blockDrag:
            guard snapshot?.blockDragState != nil else { return false }
            update = handleNativeInputEvent(
                .pointer(.updateBlockDrag(documentPoint: point, viewport: viewport))
            )

        case .blockSelectionRectangle:
            guard snapshot?.blockSelectionRectangleState != nil else { return false }
            update = handleNativeInputEvent(
                .pointer(
                    .updateBlockSelectionRectangle(
                        documentPoint: point,
                        viewport: viewport
                    )
                )
            )

        case .blockSelectionExtension:
            guard case .blocks = snapshot?.selection else { return false }
            update = handleNativeInputEvent(
                .pointer(
                    .extendBlockSelection(
                        documentPoint: point,
                        region: .gutter,
                        viewport: viewport
                    )
                )
            )
        }

        if update != nil {
            activeInputController.hide()
        }
        renderAndSyncSurface(makeFirstResponder: false)
        return true
    }

    private func handleMouseDown(documentPoint: CGPoint) {
        let viewport = currentViewport()
        let point = EditorPoint(x: Double(documentPoint.x), y: Double(documentPoint.y))
        let hitRegion: BlockHitRegion = documentPoint.x < CGFloat(editorStyle.gutterWidth)
            ? .gutter
            : .body

        switch hitRegion {
        case .gutter, .dragHandle:
            if let hit = session.hitTest(
                documentPoint: point,
                region: hitRegion,
                viewport: viewport
            ),
                selectedBlockIDs().contains(hit.blockID),
                handleNativeInputEvent(
                    .pointer(.beginBlockDrag(documentPoint: point, viewport: viewport))
                ) != nil
            {
                activeInputController.hide()
                view.window?.makeFirstResponder(editorCanvasView)
                renderAndSyncSurface(makeFirstResponder: false)
                return
            }
            guard
                handleNativeInputEvent(
                    .pointer(
                        .selectBlock(
                            documentPoint: point,
                            region: hitRegion,
                            viewport: viewport
                        )
                    )
                ) != nil
            else { return }
            activeInputController.hide()

        case .body:
            if shouldBeginBlockSelectionRectangle(at: point) {
                guard
                    handleNativeInputEvent(
                        .pointer(
                            .beginBlockSelectionRectangle(
                                documentPoint: point,
                                viewport: viewport
                            )
                        )
                    ) != nil
                else { return }
                activeInputController.hide()
                view.window?.makeFirstResponder(editorCanvasView)
                renderAndSyncSurface(makeFirstResponder: false)
                return
            }

            guard
                handleNativeInputEvent(
                    .pointer(.beginTextSelection(documentPoint: point, viewport: viewport))
                ) != nil
            else { return }
        }
        view.window?.makeFirstResponder(editorCanvasView)
        renderAndSyncSurface(makeFirstResponder: hitRegion == .body)
    }

    private func handleMouseDoubleClick(documentPoint: CGPoint) {
        guard documentPoint.x >= CGFloat(editorStyle.gutterWidth) else {
            handleMouseDown(documentPoint: documentPoint)
            return
        }

        let viewport = currentViewport()
        let point = EditorPoint(x: Double(documentPoint.x), y: Double(documentPoint.y))
        guard
            handleNativeInputEvent(
                .pointer(.selectWordOrAllText(documentPoint: point, viewport: viewport))
            ) != nil
        else { return }
        view.window?.makeFirstResponder(editorCanvasView)
        renderAndSyncSurface(makeFirstResponder: true)
    }
}

// MARK: - Selection Helpers

extension AppKitEditorViewController {
    private func activeTextPosition() -> TextPosition? {
        switch snapshot?.selection {
        case .none, .inactive, .blocks:
            return nil
        case .caret(let position):
            return position
        case .text(let selection) where selection.isSingleBlock:
            return selection.focus
        case .text:
            return nil
        }
    }

    private var hasActiveTextInput: Bool {
        activeTextPosition() != nil
    }

    private var textDragBlockSelectionThreshold: Double {
        editorStyle.fontSize * editorStyle.lineHeightMultiple
    }

    private func shouldBeginBlockSelectionRectangle(at point: EditorPoint) -> Bool {
        guard point.x >= editorStyle.gutterWidth, let snapshot else { return false }
        let cgPoint = CGPoint(x: point.x, y: point.y)
        guard
            let rendered = snapshot.visibleBlocks.first(where: {
                CGRect(editorRect: $0.frame).contains(cgPoint)
            })
        else {
            return true
        }
        guard !rendered.textRender.measureRequest.text.isEmpty else { return false }

        return !textLayouter.lineFragments(for: rendered.textRender.measureRequest).contains {
            fragment in
            documentRect(fragment.rect, in: rendered.textRender)
                .insetBy(
                    dx: -UX.lineFragmentHitOutsetX,
                    dy: -UX.lineFragmentHitOutsetY
                )
                .contains(cgPoint)
        }
    }

    private func currentActiveTextBlockID() -> BlockID? {
        activeTextPosition()?.blockID
    }

    private func snapshotRenderedBlock(for blockID: BlockID) -> EditorRenderedBlock? {
        snapshot?.visibleBlocks.first { $0.id == blockID }
    }

    private func snapshotText(for blockID: BlockID) -> String? {
        if let activeTextInput = snapshot?.activeTextInput {
            let request = activeTextInput.renderDescriptor.measureRequest
            if request.blockID == blockID {
                return request.text
            }
        }
        return snapshotRenderedBlock(for: blockID)?.textRender.measureRequest.text
    }

    private func selectedBlockIDs(in snapshot: EditorSessionSnapshot) -> Set<BlockID> {
        guard case .blocks(let selection) = snapshot.selection else { return [] }
        return Set(selection.blockIDs)
    }

    private func selectedBlockIDs() -> Set<BlockID> {
        guard let snapshot else { return [] }
        return selectedBlockIDs(in: snapshot)
    }
}

// MARK: - Drawing Helpers

extension AppKitEditorViewController {
    private func drawDropIndicator(_ indicator: EditorRect?) {
        guard let indicator else { return }
        let rect = CGRect(editorRect: indicator)
        NSColor.controlAccentColor.setFill()
        rect.insetBy(dx: UX.dropIndicatorHorizontalInset, dy: 0).fill()
    }

    private func drawBlockSelectionRectangle(_ editorRect: EditorRect?) {
        guard let editorRect, editorRect.width > 0, editorRect.height > 0 else { return }
        let rect = CGRect(editorRect: editorRect)
        NSColor.selectedContentBackgroundColor.withAlphaComponent(UX.blockSelectionFillAlpha)
            .setFill()
        rect.fill()
        NSColor.selectedContentBackgroundColor.withAlphaComponent(UX.blockSelectionStrokeAlpha)
            .setStroke()
        let path = NSBezierPath(
            rect: rect.insetBy(
                dx: UX.blockSelectionStrokeInset,
                dy: UX.blockSelectionStrokeInset
            )
        )
        path.lineWidth = UX.blockSelectionStrokeWidth
        path.stroke()
    }

    private func caretRect(for descriptor: EditorSessionActiveTextInputDescriptor) -> CGRect? {
        let request = descriptor.renderDescriptor.measureRequest
        let position = TextPosition(
            blockID: request.blockID,
            offset: descriptor.focusOffset,
            affinity: descriptor.focusAffinity
        )
        guard
            let localRect = textLayouter.caretRect(
                for: position,
                navigationContext: descriptor.navigationContext,
                in: descriptor.renderDescriptor
            )
        else { return nil }
        return documentRect(localRect, in: descriptor.renderDescriptor)
    }

    private func documentRect(
        _ localRect: EditorRect,
        in descriptor: EditorTextRenderDescriptor
    ) -> CGRect {
        let localFrame = textLayouter.textFrame(for: descriptor, measuredHeight: nil)
        return CGRect(
            x: CGFloat(localRect.x + descriptor.frame.x - localFrame.x),
            y: CGFloat(localRect.y + descriptor.frame.y - localFrame.y),
            width: CGFloat(localRect.width),
            height: CGFloat(localRect.height)
        )
    }
}
