import AppKit
import Foundation
import SlopadAppKitTextKit
import SlopadAppKitUI
import SlopadEngine

@MainActor
final class DebugViewController: NSViewController {
    // MARK: - Private Types

    private enum UX {
        static let initialViewSize = NSSize(width: 920, height: 680)
    }

    // MARK: - Dependencies

    let editorStyle = TextKitEditorStyle()

    private lazy var editorViewController = makeEditorViewController()

    // MARK: - Debug State

    var debugHUDRevisionComparison: EditorSnapshotRevisionComparison?

    private let initialBlocks: [EditorBlockInput]
    private let initialSelection: EditorSelection
    private let focusOnAppear: Bool
    private var previousSnapshot: EditorSessionSnapshot?

    // MARK: - AppKitUI Facade

    var session: EditorSession {
        editorViewController.session
    }

    var snapshot: EditorSessionSnapshot? {
        editorViewController.snapshot
    }

    var scrollView: NSScrollView {
        editorViewController.scrollView
    }

    var activeNativeText: String {
        editorViewController.activeNativeText
    }

    var activeNativeSelectedRange: NSRange {
        editorViewController.activeNativeSelectedRange
    }

    var hasActiveNativeMarkedText: Bool {
        editorViewController.hasActiveNativeMarkedText
    }

    // MARK: - Init

    init(
        blocks: [EditorBlockInput],
        selection: EditorSelection,
        focusOnAppear: Bool = false
    ) {
        self.initialBlocks = blocks
        self.initialSelection = selection
        self.focusOnAppear = focusOnAppear
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = makeRootView()
        installEditorViewController()
    }

    // MARK: - Rendering

    func renderAndSyncSurface(
        makeFirstResponder: Bool,
        scrollSelectionIntoView: Bool = false
    ) {
        editorViewController.renderAndSyncSurface(
            makeFirstResponder: makeFirstResponder,
            scrollSelectionIntoView: scrollSelectionIntoView
        )
    }

    func renderCanvasPreservingNativeSurface() {
        editorViewController.renderPreservingNativeSurface()
    }

    func currentViewport() -> EditorViewport {
        editorViewController.currentViewport()
    }

    // MARK: - Input

    func focus(blockID: BlockID, offset: Int) {
        _ = handleNativeInputEvent(
            .activeTextSelectionChanged(
                blockID: blockID,
                selectedRange: .point(offset)
            )
        )
    }

    func replaceActiveText(
        _ text: String,
        preservingNativeSelection: Bool = false,
        blockID explicitBlockID: BlockID? = nil
    ) {
        editorViewController.replaceActiveText(
            text,
            preservingNativeSelection: preservingNativeSelection,
            blockID: explicitBlockID
        )
    }

    @discardableResult
    func handleNativeInputEvent(_ inputEvent: EditorInputEvent) -> EditorUpdate? {
        editorViewController.handleInputWithoutRendering(inputEvent)
    }

    func handleMouseDown(documentPoint: CGPoint) {
        editorViewController.handleMouseDown(documentPoint: documentPoint, clickCount: 1)
    }

    func handleMouseDoubleClick(documentPoint: CGPoint) {
        editorViewController.handleMouseDown(documentPoint: documentPoint, clickCount: 2)
    }

    func handleMouseDragged(documentPoint: CGPoint) {
        editorViewController.handleMouseDragged(documentPoint: documentPoint)
    }

    func handleMouseUp(documentPoint: CGPoint) {
        editorViewController.handleMouseUp(documentPoint: documentPoint)
    }

    func handleNativeCommand(_ commandSelector: Selector) -> Bool {
        editorViewController.handleNativeCommand(commandSelector)
    }

    func insertTextFromNativeSurface(_ text: String, replacementRange: NSRange) {
        editorViewController.insertTextFromNativeSurface(text, replacementRange: replacementRange)
    }

    func setMarkedTextFromNativeSurface(
        _ text: String,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        editorViewController.setMarkedTextFromNativeSurface(
            text,
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
    }

    func unmarkTextFromNativeSurface() {
        editorViewController.unmarkTextFromNativeSurface()
    }

    func hideActiveNativeSurface() {
        editorViewController.hideActiveNativeSurface()
    }

    // MARK: - Snapshot Helpers

    fileprivate func currentSnapshot() -> EditorSessionSnapshot? {
        snapshot
    }

    func snapshotRenderedBlock(for blockID: BlockID) -> EditorRenderedBlock? {
        snapshot?.visibleBlocks.first { $0.id == blockID }
    }

    func snapshotText(for blockID: BlockID) -> String? {
        if let activeTextInput = snapshot?.activeTextInput {
            let request = activeTextInput.renderDescriptor.measureRequest
            if request.blockID == blockID {
                return request.text
            }
        }
        return snapshotRenderedBlock(for: blockID)?.textRender.measureRequest.text
    }

    func snapshotRootBlockIDs() -> [BlockID] {
        snapshot?.visibleBlocks.compactMap { rendered in
            rendered.depth == 0 ? rendered.id : nil
        } ?? []
    }

    // MARK: - Debug Mutations

    func resetDocument(blocks: [EditorBlockInput], selection: EditorSelection) {
        previousSnapshot = nil
        debugHUDRevisionComparison = nil
        editorViewController.resetDocumentWithoutRendering(blocks: blocks, selection: selection)
    }

    func scrollDocument(to y: Double) {
        editorViewController.scrollDocumentWithoutRendering(to: y)
    }

    // MARK: - Setup

    private func makeRootView() -> NSView {
        let rootView = NSView(frame: NSRect(origin: .zero, size: UX.initialViewSize))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        return rootView
    }

    private func makeEditorViewController() -> AppKitEditorViewController {
        let viewController = AppKitEditorViewController(
            blocks: initialBlocks,
            selection: initialSelection,
            style: editorStyle,
            focusOnAppear: focusOnAppear
        )
        viewController.onSnapshotChanged = { [weak self] snapshot in
            self?.handleSnapshotChanged(snapshot)
        }
        viewController.onDrawOverlay = { [weak self] _, snapshot in
            self?.drawDebugHUD(snapshot)
        }
        return viewController
    }

    private func installEditorViewController() {
        let child = editorViewController
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)

        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func handleSnapshotChanged(_ nextSnapshot: EditorSessionSnapshot) {
        debugHUDRevisionComparison = nextSnapshot.revision.comparison(from: previousSnapshot?.revision)
        previousSnapshot = nextSnapshot
    }
}
