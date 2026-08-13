import AppKit
import Foundation
import SlopadEditorAppKitTextKit
import SlopadEditorEngine

// MARK: - AppKitEditorViewController

@MainActor
public final class AppKitEditorViewController: NSViewController {
    private enum Accessibility {
        static let editorIdentifier = "AppKitEditorCanvas"
        static let editorLabel = "Editor"
    }

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

    private struct TodoCheckboxGesture {
        let blockID: BlockID
        let hitRect: CGRect
        var isInside: Bool
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

    /// The full height of the laid-out document, excluding the editor's bottom padding.
    ///
    /// This is the value an inline editor sizes itself to. It is `0` until the first
    /// layout settles.
    public private(set) var contentHeight: Double = 0

    /// Called when the document height changes, and only then.
    ///
    /// `onSnapshotChanged` also carries `totalHeight`, but it fires on every scroll and
    /// render pass, so a host that only wants to grow a frame would be recomputing on
    /// every keystroke and every scroll tick. This fires when the number a host would act
    /// on actually moved.
    public var onContentHeightChange: ((Double) -> Void)?
    public var blockChromeRenderer: any AppKitBlockChromeRenderer
    public var onSnapshotChanged: ((EditorSessionSnapshot) -> Void)?
    public var onUpdate: ((EditorUpdate) -> Void)?

    // MARK: - Package State

    package let scrollView = NSScrollView()
    package private(set) var session: EditorSession
    package var onDrawOverlay: ((NSRect, EditorSessionSnapshot) -> Void)?
    package var onDrawCompleted: ((NSRect, UInt64) -> Void)?

    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        package var preparedLayoutInstrumentation: TextKitPreparedLayoutInstrumentationSnapshot {
            textLayouter.contextPreparedLayoutInstrumentation
        }
    #endif

    var canvasView: AppKitEditorCanvasView {
        editorCanvasView
    }

    // MARK: - Private State

    private var textSystem: AppKitTextSystem
    private var editorAccessibilityIdentifier = Accessibility.editorIdentifier
    private var editorAccessibilityLabel = Accessibility.editorLabel
    private var textLayouter: TextKitBlockTextLayouter {
        textSystem.textLayouter
    }
    private var textRenderer: TextKitBlockRenderer {
        textSystem.textRenderer
    }
    private var textInputDecorationRenderer: AppKitTextInputDecorationRenderer {
        textSystem.textInputDecorationRenderer
    }
    #if DEBUG
        package var nativeInputTraceHandler: AppKitNativeInputTraceHandler?

        private lazy var editorCanvasView = AppKitEditorCanvasView(
            handler: self,
            nativeInputTraceHandler: { [weak self] event in
                self?.nativeInputTraceHandler?(event)
            }
        )
        private lazy var activeInputController = AppKitActiveInputController(
            owner: self,
            nativeInputTraceHandler: { [weak self] event in
                self?.nativeInputTraceHandler?(event)
            }
        )
    #else
        private lazy var editorCanvasView = AppKitEditorCanvasView(handler: self)
        private lazy var activeInputController = AppKitActiveInputController(owner: self)
    #endif
    private lazy var slashCommandOverlay: AppKitSlashCommandOverlay = {
        let overlay = AppKitSlashCommandOverlay(frame: .zero)
        overlay.onCommandRequested = { [weak self] command, source in
            self?.selectSlashCommand(command, source: source)
        }
        overlay.onDismissRequested = { [weak self] in
            self?.session.dismissSlashCommand()
        }
        return overlay
    }()
    private lazy var floatingFormattingToolbar: AppKitFloatingFormattingToolbar = {
        let toolbar = AppKitFloatingFormattingToolbar(frame: .zero)
        toolbar.onActionRequested = { [weak self] action in
            guard let self else { return }
            let canvasWasFirstResponder = view.window?.firstResponder === editorCanvasView
            _ = perform(
                action,
                makeFirstResponder: canvasWasFirstResponder,
                scrollSelectionIntoView: false
            )
        }
        return toolbar
    }()
    lazy var dragAutoscrollController = AppKitDragAutoscrollController(
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
    private let snapshotPublisher = AppKitSnapshotPublisher()
    private var todoCheckboxGesture: TodoCheckboxGesture?
    private var isPointerSelectionGestureActive = false
    private let focusOnAppear: Bool
    /// A `setFocused` call that arrived before the view had a window.
    private var pendingFocus: Bool?

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
        textSystem.setActivePreparedLayoutBlockID(session.activeTextBlockID)
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
        if let pendingFocus {
            self.pendingFocus = nil
            setFocused(pendingFocus)
        } else if focusOnAppear {
            setFocused(true)
        }
    }

    // MARK: - Public Focus

    /// Whether the editor currently holds keyboard focus.
    ///
    /// Maintained from the canvas's responder transitions rather than read from the window
    /// on demand, so it stays correct inside `onFocusChange` — AppKit has not updated
    /// `window.firstResponder` yet at the moment a responder is told it became one.
    public private(set) var isFocused: Bool = false

    /// Called whenever focus changes, including changes the host did not initiate.
    ///
    /// Fires only on an actual transition, so a host can drive it from a binding without
    /// filtering repeats itself.
    public var onFocusChange: ((Bool) -> Void)?

    /// Gives the editor keyboard focus, or gives it up.
    ///
    /// This is synchronized: `isFocused` and `onFocusChange` have already settled when the
    /// call returns. Before the view has a window the request is remembered and applied on
    /// `viewDidAppear`, because a host binding is usually evaluated before the view is
    /// mounted.
    ///
    /// Giving up focus only resigns focus this editor actually holds. Blurring
    /// unconditionally would let a host that is merely disabling itself steal focus from an
    /// unrelated view.
    public func setFocused(_ isFocused: Bool) {
        guard let window = view.window else {
            pendingFocus = isFocused
            return
        }
        guard isFocused != self.isFocused else { return }

        if isFocused {
            window.makeFirstResponder(editorCanvasView)
        } else {
            window.makeFirstResponder(nil)
        }

        // The responder change alone does not move the native input surface. Without this
        // the editor would hold focus while IME still targets the geometry from before.
        renderAndSyncSurface(makeFirstResponder: false)
    }

    /// Reconciles the observable focus state with a canvas responder transition.
    func canvasFocusDidChange(_ isFocused: Bool) {
        guard isFocused != self.isFocused else { return }
        self.isFocused = isFocused
        onFocusChange?(isFocused)
    }

    // MARK: - Unhandled Actions

    /// Called when the engine refused a semantic action, so the host can take it over.
    ///
    /// Return `true` if the host consumed the action, `false` to fall back to the editor's
    /// default handling for it. `handleEscapeInputCommand` is the motivating case: Escape
    /// walks caret → blocks → inactive and then returns nothing, and until now there was no
    /// signal at all that the editor had run out of things to do with it.
    ///
    /// This is a result notification, not a policy hook — it reports what the engine
    /// already decided and never gets to change that decision. Native key, pointer and IME
    /// callbacks stay adapter-owned.
    public var onUnhandledAction: ((AppKitEditorAction) -> Bool)?

    /// Guards against a callback that performs another action which is also refused.
    private var isReportingUnhandledAction = false

    /// Reports a refused action and answers whether it ended up handled.
    ///
    /// `defaultHandled` is what the call site did before this callback existed, so a host
    /// that never sets `onUnhandledAction` observes no behavior change anywhere.
    func reportUnhandledAction(
        _ action: AppKitEditorAction,
        defaultHandled: Bool
    ) -> Bool {
        guard let onUnhandledAction, !isReportingUnhandledAction else {
            return defaultHandled
        }
        isReportingUnhandledAction = true
        defer { isReportingUnhandledAction = false }
        return onUnhandledAction(action)
    }

    // MARK: - Public Actions

    package func renderAndSyncSurface(
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

    /// Configures the native editor input surface for a host's accessibility namespace.
    ///
    /// Passing `nil` restores the editor defaults. The scroll surface continues to route
    /// input to the single native canvas; this does not add a proxy control or state owner.
    /// Its value is the ordered plain text and its title is the ordered canonical block-kind
    /// summary (for example, `Heading 1, Todo Unchecked`) so native automation can prove
    /// prefix conversion without inferring structure from serialized Markdown text.
    public func configureEditorAccessibility(identifier: String?, label: String?) {
        editorAccessibilityIdentifier = identifier ?? Accessibility.editorIdentifier
        editorAccessibilityLabel = label ?? Accessibility.editorLabel
        applyEditorAccessibilityConfiguration()
    }

    /// Replaces the adapter-owned TextKit layout and drawing pipeline from one style.
    ///
    /// The operation synchronizes the Session snapshot and canvas before returning while
    /// preserving live marked text, native selection, viewport, and responder ownership.
    public func updateEditorStyle(_ style: AppKitEditorStyle) {
        guard style != editorStyle else { return }

        let replacementTextSystem = AppKitTextSystem(style: style)
        replacementTextSystem.setActivePreparedLayoutBlockID(session.activeTextBlockID)
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
        todoCheckboxGesture = nil
        isPointerSelectionGestureActive = false
        textSystem.setActivePreparedLayoutBlockID(nil)
        textSystem.removeAllPreparedLayouts()
        let replacementSession = EditorSession(
            blocks: blocks,
            selection: selection,
            textLayouter: textLayouter
        )
        textSystem.setActivePreparedLayoutBlockID(replacementSession.activeTextBlockID)
        session = replacementSession
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
        let update = handleInput(
            action.inputEvent(viewport: currentViewport()),
            makeFirstResponder: makeFirstResponder,
            scrollSelectionIntoView: scrollSelectionIntoView
        )
        if update == nil {
            // No responder chain to fall back to on a programmatic action, so the callback
            // is the only escalation path here.
            _ = reportUnhandledAction(action, defaultHandled: false)
        }
        return update
    }

    /// Package-only built-in chrome query. Hosts do not receive command-state policy.
    package var commandState: EditorCommandState {
        snapshot?.commandState ?? session.commandState()
    }

    /// Synchronized package action used by built-in adapter chrome.
    @discardableResult
    package func perform(
        _ action: EditorCommandAction,
        makeFirstResponder: Bool = true,
        scrollSelectionIntoView: Bool = true
    ) -> EditorUpdate? {
        _ = commitActiveComposition()
        guard let update = session.apply(action) else { return nil }
        onUpdate?(update)
        renderAndSyncSurface(
            makeFirstResponder: makeFirstResponder,
            scrollSelectionIntoView: scrollSelectionIntoView
        )
        return update
    }

    package func todoState(blockID: BlockID) -> EditorToggleState {
        session.todoState(blockID: blockID)
    }

    /// The exact clicked block is preserved across the adapter boundary.
    @discardableResult
    package func toggleTodo(blockID: BlockID) -> EditorUpdate? {
        guard let update = session.toggleTodo(blockID: blockID) else { return nil }
        onUpdate?(update)
        let canvasWasFirstResponder = view.window?.firstResponder === editorCanvasView
        if hasActiveNativeMarkedText {
            renderCanvasPreservingNativeSurface(
                makeFirstResponder: canvasWasFirstResponder,
                nativeStateIsAuthoritative: true
            )
        } else {
            renderAndSyncSurface(
                makeFirstResponder: canvasWasFirstResponder,
                scrollSelectionIntoView: false
            )
        }
        return update
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

    var activeNativeMarkedReplacementRange: NSRange? {
        activeInputController.activeMarkedReplacementRange
    }

    var activeNativeMarkedDocumentText: String? {
        activeInputController.activeMarkedDocumentText
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
        applyEditorAccessibilityConfiguration()
        view.addSubview(scrollView)
        view.addSubview(slashCommandOverlay)
        view.addSubview(floatingFormattingToolbar)
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

    private func applyEditorAccessibilityConfiguration() {
        scrollView.setAccessibilityIdentifier(editorAccessibilityIdentifier)
        scrollView.setAccessibilityLabel(editorAccessibilityLabel)
        scrollView.setAccessibilityEnabled(true)
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
            // Reported from the settled snapshot rather than from each render pass, so a
            // host binding its frame to this never sees the intermediate heights the
            // convergence loop produces.
            notifyContentHeightIfChanged(finalSnapshot.totalHeight)
            publishSnapshot(finalSnapshot, viewport: finalViewport)
        }
    }

    /// Emits `onContentHeightChange` when the settled document height actually moved.
    private func notifyContentHeightIfChanged(_ height: Double) {
        guard contentHeight != height else { return }
        contentHeight = height
        onContentHeightChange?(height)
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
        textSystem.setActivePreparedLayoutBlockID(session.activeTextBlockID)
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

        synchronizeInsertionPoint(with: renderedSurface.snapshot)
        synchronizeEditorAccessibilityProjection()
        invalidateVisibleCanvas()
        synchronizeSlashCommandOverlay(with: renderedSurface.snapshot)
        synchronizeFloatingFormattingToolbar(with: renderedSurface.snapshot)
        return renderedSurface
    }

    private func synchronizeEditorAccessibilityProjection() {
        let blocks = session.documentSnapshot.blocks
        let value = blocks
            .map(\.content.text)
            .joined(separator: "\n")
        if scrollView.accessibilityValue() as? String != value {
            scrollView.setAccessibilityValue(value)
            NSAccessibility.post(element: scrollView, notification: .valueChanged)
        }

        let blockStructure = blocks
            .map { accessibilityName(for: $0.kind) }
            .joined(separator: ", ")
        if scrollView.accessibilityTitle() != blockStructure {
            scrollView.setAccessibilityTitle(blockStructure)
        }
    }

    private func accessibilityName(for kind: BlockKind) -> String {
        switch kind {
        case .paragraph:
            "Paragraph"
        case .heading(let level):
            "Heading \(level.rawValue)"
        case .unorderedListItem:
            "Unordered List Item"
        case .orderedListItem(let restartNumber):
            if let restartNumber {
                "Ordered List Item \(restartNumber)"
            } else {
                "Ordered List Item"
            }
        case .quote:
            "Quote"
        case .codeBlock(let language):
            if let language, !language.isEmpty {
                "Code Block \(language)"
            } else {
                "Code Block"
            }
        case .divider:
            "Divider"
        case .todo(let isChecked):
            isChecked ? "Todo Checked" : "Todo Unchecked"
        }
    }

    package func handlePreparedLayoutMemoryPressure(
        _ pressure: TextKitPreparedLayoutMemoryPressure
    ) {
        textSystem.handlePreparedLayoutMemoryPressure(pressure)
    }

    private func isActiveSnapshotPublication(
        _ renderedSurface: (viewport: EditorViewport, snapshot: EditorSessionSnapshot)
    ) -> Bool {
        let isSameSnapshot = snapshotPublisher.isActivePublication(
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
        snapshotPublisher.publish(snapshot, viewport: viewport, deliver: onSnapshotChanged)
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

    private func synchronizeInsertionPoint(with snapshot: EditorSessionSnapshot) {
        guard
            case .caret = snapshot.selection,
            let caretRect = snapshot.activeTextInput?.caretRect
        else {
            editorCanvasView.updateInsertionPoint(nil)
            return
        }
        editorCanvasView.updateInsertionPoint(CGRect(editorRect: caretRect))
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
        let selectedBlockIDs = snapshot.selectionPresentation.visibleBlockSelectionIDs
        let activeTextBlockID = activeChromeBlockID(in: snapshot)
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
            if case .todo(let isChecked) = rendered.kind {
                AppKitTodoCheckboxControl.draw(
                    isChecked: isChecked,
                    blockFrame: blockFrame,
                    style: editorStyle,
                    isPressed: todoCheckboxGesture?.blockID == rendered.id
                        && todoCheckboxGesture?.isInside == true
                )
            }
        }

        for rendered in snapshot.visibleBlocks {
            textRenderer.draw(rendered.textRender, context: cgContext)
        }
        textInputDecorationRenderer.draw(
            snapshot.selectionPresentation,
            graphicsContext: cgContext
        )
        drawBlockSelectionRectangle(snapshot.blockSelectionRectangleState?.rect)
        drawDropIndicator(snapshot.blockDragState?.dropIndicator)
        onDrawOverlay?(dirtyRect, snapshot)
    }

    // MARK: - Mouse Events

    package func handleMouseDown(documentPoint: CGPoint, clickCount: Int) {
        dragAutoscrollController.stop()
        if beginTodoCheckboxGesture(at: documentPoint) {
            return
        }
        isPointerSelectionGestureActive = true
        if clickCount >= 2 {
            handleMouseDoubleClick(documentPoint: documentPoint)
        } else {
            handleMouseDown(documentPoint: documentPoint)
        }
    }

    package func handleMouseDragged(documentPoint: CGPoint) {
        if updateTodoCheckboxGesture(at: documentPoint) {
            return
        }
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

        if applyDragUpdate(kind: .textSelection, documentPoint: documentPoint) {
            dragAutoscrollController.update(
                kind: .textSelection,
                documentPoint: documentPoint
            )
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
        if endTodoCheckboxGesture(at: documentPoint) {
            return
        }
        isPointerSelectionGestureActive = false
        let viewport = currentViewport()
        let point = EditorPoint(x: Double(documentPoint.x), y: Double(documentPoint.y))
        if snapshot?.blockDragState != nil {
            handleNativeInputEvent(
                .pointer(.endBlockDrag(documentPoint: point, viewport: viewport)))
            renderAndSyncSurface(makeFirstResponder: false)
        } else if snapshot?.blockSelectionRectangleState != nil {
            handleNativeInputEvent(.pointer(.endBlockSelectionRectangle))
            renderAndSyncSurface(makeFirstResponder: false)
        } else {
            handleNativeInputEvent(.pointer(.endTextSelection))
            handleNativeInputEvent(.pointer(.endBlockSelection))
            renderAndSyncSurface(makeFirstResponder: false)
        }
    }

    // MARK: - Native Commands

    package func handleNativeCommand(_ commandSelector: Selector) -> Bool {
        if slashCommandOverlay.handleCommand(commandSelector) {
            return true
        }
        return activeInputController.handleCommand(commandSelector)
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
        #if DEBUG
            nativeInputTraceHandler?(
                AppKitNativeInputTraceEvent(
                    category: .firstRect,
                    phase: .before,
                    requestedRange: AppKitNativeInputTraceRange(range),
                    blockToken: AppKitNativeInputTraceBlockToken.make(
                        activeInputController.activeBlockID
                    ),
                    inputContextAvailable: editorCanvasView.inputContext != nil,
                    inputSourceID: editorCanvasView.inputContext?.selectedKeyboardInputSource
                )
            )
        #endif
        guard
            let activeTextInput = snapshot?.activeTextInput,
            let caretRect = caretRect(for: activeTextInput)
        else {
            #if DEBUG
                nativeInputTraceHandler?(
                    AppKitNativeInputTraceEvent(
                        category: .firstRect,
                        phase: .after,
                        requestedRange: AppKitNativeInputTraceRange(range),
                        resultRect: AppKitNativeInputTraceRect(.zero),
                        resultAvailable: false,
                        blockToken: AppKitNativeInputTraceBlockToken.make(
                            activeInputController.activeBlockID
                        ),
                        inputContextAvailable: editorCanvasView.inputContext != nil,
                        inputSourceID: editorCanvasView.inputContext?.selectedKeyboardInputSource
                    )
                )
            #endif
            return .zero
        }
        let windowRect = editorCanvasView.convert(caretRect, to: nil)
        let result = view.window?.convertToScreen(windowRect) ?? windowRect
        #if DEBUG
            nativeInputTraceHandler?(
                AppKitNativeInputTraceEvent(
                    category: .firstRect,
                    phase: .after,
                    requestedRange: AppKitNativeInputTraceRange(range),
                    resultRect: AppKitNativeInputTraceRect(result),
                    resultAvailable: true,
                    blockToken: AppKitNativeInputTraceBlockToken.make(
                        activeTextInput.renderDescriptor.measureRequest.blockID
                    ),
                    inputContextAvailable: editorCanvasView.inputContext != nil,
                    inputSourceID: editorCanvasView.inputContext?.selectedKeyboardInputSource
                )
            )
        #endif
        return result
    }
}

// MARK: - Slash Command Overlay

extension AppKitEditorViewController {
    private func synchronizeSlashCommandOverlay(with snapshot: EditorSessionSnapshot) {
        let anchorInContainer = snapshot.slashCommand?.anchor.map { anchor in
            editorCanvasView.convert(CGRect(editorRect: anchor), to: view)
        }
        slashCommandOverlay.synchronize(
            presentation: snapshot.slashCommand,
            anchorInContainer: anchorInContainer,
            containerBounds: view.bounds
        )
    }

    /// The overlay only chooses a catalog value. Session validates the opaque source and owns
    /// the query removal plus block conversion transaction.
    private func selectSlashCommand(
        _ command: EditorSlashCommand,
        source: EditorSlashCommandSource
    ) {
        guard let update = session.applySlashCommand(command, source: source)
        else {
            slashCommandOverlay.dismiss()
            return
        }
        textSystem.setActivePreparedLayoutBlockID(
            preparedLayoutPinnedBlockID(in: update.selection)
        )
        onUpdate?(update)
        renderAndSyncSurface(makeFirstResponder: true, scrollSelectionIntoView: true)
    }

    package var isSlashCommandMenuPresented: Bool {
        slashCommandOverlay.isPresented
    }

    package var slashCommandMenuFrame: NSRect? {
        slashCommandOverlay.isPresented ? slashCommandOverlay.frame : nil
    }
}

// MARK: - Floating Formatting Toolbar

extension AppKitEditorViewController {
    private func synchronizeFloatingFormattingToolbar(with snapshot: EditorSessionSnapshot) {
        let presentation = snapshot.selectionPresentation
        let documentAnchor =
            isPointerSelectionGestureActive
            ? nil
            : presentation.focusRect ?? presentation.visibleBounds
        let anchorInContainer = documentAnchor.map {
            editorCanvasView.convert(CGRect(editorRect: $0), to: view)
        }
        floatingFormattingToolbar.synchronize(
            commandState: snapshot.commandState,
            presentation: presentation,
            anchorInContainer: anchorInContainer,
            containerBounds: view.bounds
        )
    }

    package var isFloatingFormattingToolbarPresented: Bool {
        !floatingFormattingToolbar.isHidden
    }

    package var floatingFormattingToolbarFrame: NSRect? {
        isFloatingFormattingToolbarPresented ? floatingFormattingToolbar.frame : nil
    }

    package func floatingFormattingToolbarItemState(
        _ item: AppKitFloatingFormattingToolbar.Item
    ) -> AppKitFloatingFormattingToolbar.ItemState? {
        floatingFormattingToolbar.itemState(item)
    }

    package func performFloatingFormattingToolbarItem(
        _ item: AppKitFloatingFormattingToolbar.Item
    ) {
        floatingFormattingToolbar.perform(item)
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

    func clipboardWritePlan() -> EditorClipboardWritePlan? {
        session.clipboardWritePlan()
    }

    @discardableResult
    func handleNativeInputEvent(_ inputEvent: EditorInputEvent) -> EditorUpdate? {
        guard let update = session.handleInput(inputEvent) else { return nil }
        textSystem.setActivePreparedLayoutBlockID(
            preparedLayoutPinnedBlockID(in: update.selection)
        )
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
    package func todoCheckboxHitRect(blockID: BlockID) -> CGRect? {
        guard
            let rendered = snapshot?.visibleBlocks.first(where: { $0.id == blockID }),
            case .todo = rendered.kind
        else { return nil }
        return AppKitTodoCheckboxControl.hitRect(
            blockFrame: CGRect(editorRect: rendered.frame),
            style: editorStyle
        )
    }

    private func beginTodoCheckboxGesture(at documentPoint: CGPoint) -> Bool {
        guard let hit = todoCheckboxHit(at: documentPoint) else { return false }
        todoCheckboxGesture = TodoCheckboxGesture(
            blockID: hit.blockID,
            hitRect: hit.rect,
            isInside: true
        )
        editorCanvasView.setNeedsDisplay(hit.rect.insetBy(dx: -4, dy: -4))
        return true
    }

    private func updateTodoCheckboxGesture(at documentPoint: CGPoint) -> Bool {
        guard var gesture = todoCheckboxGesture else { return false }
        let isInside = gesture.hitRect.contains(documentPoint)
        if gesture.isInside != isInside {
            gesture.isInside = isInside
            todoCheckboxGesture = gesture
            editorCanvasView.setNeedsDisplay(gesture.hitRect.insetBy(dx: -4, dy: -4))
        }
        return true
    }

    private func endTodoCheckboxGesture(at documentPoint: CGPoint) -> Bool {
        guard let gesture = todoCheckboxGesture else { return false }
        todoCheckboxGesture = nil
        editorCanvasView.setNeedsDisplay(gesture.hitRect.insetBy(dx: -4, dy: -4))
        guard gesture.hitRect.contains(documentPoint) else { return true }
        _ = toggleTodo(blockID: gesture.blockID)
        return true
    }

    private func todoCheckboxHit(at documentPoint: CGPoint) -> (blockID: BlockID, rect: CGRect)? {
        guard let snapshot else { return nil }
        for rendered in snapshot.visibleBlocks {
            guard case .todo = rendered.kind else { continue }
            let rect = AppKitTodoCheckboxControl.hitRect(
                blockFrame: CGRect(editorRect: rendered.frame),
                style: editorStyle
            )
            if rect.contains(documentPoint) {
                return (rendered.id, rect)
            }
        }
        return nil
    }

    @discardableResult
    private func applyDragUpdate(
        kind: AppKitDragAutoscrollKind,
        documentPoint: CGPoint
    ) -> Bool {
        let viewport = currentViewport()
        let point = EditorPoint(x: Double(documentPoint.x), y: Double(documentPoint.y))
        let update: EditorUpdate?

        switch kind {
        case .textSelection:
            update = handleNativeInputEvent(
                .pointer(
                    .updateTextSelection(
                        documentPoint: point,
                        viewport: viewport
                    )
                )
            )

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

        guard update != nil else { return false }
        let isTextSelection: Bool
        switch kind {
        case .textSelection: isTextSelection = true
        case .blockDrag, .blockSelectionRectangle, .blockSelectionExtension:
            isTextSelection = false
        }
        if !isTextSelection {
            activeInputController.hide()
        }
        renderAndSyncSurface(makeFirstResponder: isTextSelection)
        return true
    }

    private func handleMouseDown(documentPoint: CGPoint) {
        let viewport = currentViewport()
        let point = EditorPoint(x: Double(documentPoint.x), y: Double(documentPoint.y))
        let hitRegion: BlockHitRegion =
            documentPoint.x < CGFloat(editorStyle.gutterWidth)
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
        case .text(let selection):
            return selection.focus
        }
    }

    private var hasActiveTextInput: Bool {
        activeTextPosition() != nil
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

        return !session.textLineFragmentRects(in: rendered.textRender).contains { rect in
            CGRect(editorRect: rect)
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

    private func preparedLayoutPinnedBlockID(in selection: EditorSelection) -> BlockID? {
        switch selection {
        case .caret(let position):
            return position.blockID
        case .text(let selection):
            return selection.focus.blockID
        case .inactive, .blocks:
            return nil
        }
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

    /// Cross-block text selection keeps its focus block as the native input host, but that
    /// implementation detail must not make one endpoint look structurally selected.
    private func activeChromeBlockID(in snapshot: EditorSessionSnapshot) -> BlockID? {
        if case .text(let selection) = snapshot.selection, !selection.isSingleBlock {
            return nil
        }
        return snapshot.activeTextInput?.renderDescriptor.measureRequest.blockID
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
        descriptor.caretRect.map(CGRect.init)
    }
}
