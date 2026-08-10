import AppKit
import SlopadAppKit

@MainActor
private struct HostChromeRenderer: AppKitBlockChromeRenderer {
    func drawChrome(_ context: AppKitBlockChromeRenderContext) {
        let width = min(CGFloat(context.style.gutterWidth), context.blockFrame.width)
        let gutter = CGRect(
            x: context.blockFrame.minX,
            y: context.blockFrame.minY,
            width: width,
            height: context.blockFrame.height
        )
        let color = context.isSelected
            ? NSColor.selectedContentBackgroundColor
            : NSColor.separatorColor
        context.graphicsContext.setFillColor(color.cgColor)
        context.graphicsContext.fill(gutter)
    }
}

@main
@MainActor
private struct DownstreamAppKitHost {
    static func main() {
        _ = NSApplication.shared
        let blockID: BlockID = "fixture-root"
        let style = AppKitEditorStyle(
            fontName: "System",
            fontSize: 17,
            lineHeightMultiple: 1.3,
            gutterWidth: 48,
            contentHorizontalPadding: 16,
            blockIndentWidth: 22,
            languageIdentifier: "en-US"
        )
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    kind: .todo(isChecked: false),
                    content: BlockContent(text: "Public-only downstream host")
                )
            ],
            selection: .caret(blockID: blockID, offset: 0),
            style: style,
            blockChromeRenderer: HostChromeRenderer()
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        controller.view.frame = window.contentView?.bounds ?? .zero
        controller.view.layoutSubtreeIfNeeded()

        precondition(window.contentViewController === controller)
        precondition(controller.view.window === window)

        do {
            try exercisePublicHostContract(
                controller,
                window: window,
                blockID: blockID,
                style: style
            )
        } catch {
            fatalError("Public SlopadAppKit contract failed: \(error)")
        }

        controller.setFocused(false)
        window.orderOut(nil)
        window.contentViewController = nil
        precondition(window.contentViewController == nil)
        precondition(controller.view.window == nil)
        window.close()
    }

    private static func exercisePublicHostContract(
        _ controller: AppKitEditorViewController,
        window: NSWindow,
        blockID: BlockID,
        style: AppKitEditorStyle
    ) throws {
        // A persistence host holds a committed change token and decides later whether it is
        // still worth writing. Both halves have to be public values.
        var capturedToken: (epoch: EditorSessionEpoch, revision: EditorDocumentRevision)?
        var capturedCommittedSnapshot: EditorDocumentSnapshot?
        controller.onSnapshotChanged = { _ in }
        controller.onUpdate = { [weak controller] update in
            guard let revision = update.committedDocumentRevision else { return }
            guard let documentSnapshot = controller?.documentSnapshot else {
                preconditionFailure("Committed observation lost its mounted controller")
            }
            precondition(documentSnapshot.revision == revision)
            precondition(documentSnapshot.epoch == update.epoch)
            capturedToken = (update.epoch, revision)
            capturedCommittedSnapshot = documentSnapshot
        }
        controller.blockChromeRenderer = HostChromeRenderer()
        _ = controller.editorStyle == style
        _ = controller.snapshot
        _ = controller.documentSnapshot

        // The lifecycle gate mutates only after the production view is mounted. The
        // callback reads the matching committed snapshot synchronously, like a save host.
        let editUpdate = controller.perform(
            .insertText("Mounted: "),
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )
        precondition(editUpdate?.committedDocumentRevision?.rawValue == 1)
        precondition(capturedToken?.revision == editUpdate?.committedDocumentRevision)
        precondition(
            capturedCommittedSnapshot?.blocks.first?.content.text.hasPrefix("Mounted: ") == true
        )

        let assistantContext: EditorDocumentContextSnapshot =
            try controller.documentContextSnapshot()
        switch assistantContext.selectedContent {
        case .none:
            break
        case .text(let selectedText):
            _ = selectedText.fragments.map(\.sourceRange)
        case .blocks(let selectedBlocks):
            _ = selectedBlocks.rootBlockIDs
        }
        let assistantUpdate = try controller.applyDocumentPatch(
            EditorDocumentPatch(
                source: assistantContext.source,
                replacementBlocks: [
                    EditorBlockInput(
                        id: blockID,
                        kind: .todo(isChecked: true),
                        content: BlockContent(text: "Updated by assistant contract")
                    )
                ],
                selectionAfter: .caret(blockID: blockID, offset: 7)
            )
        )
        precondition(assistantUpdate?.committedDocumentRevision?.rawValue == 2)
        let noOpContext = try controller.documentContextSnapshot()
        let noOpUpdate = try controller.applyDocumentPatch(
            EditorDocumentPatch(
                source: noOpContext.source,
                replacementBlocks: noOpContext.document.blocks,
                selectionAfter: noOpContext.selection
            )
        )
        precondition(noOpUpdate == nil)

        // An inline host sizes its container from the document height without subscribing
        // to render snapshots.
        var observedHeights: [Double] = []
        controller.onContentHeightChange = { observedHeights.append($0) }
        _ = controller.contentHeight
        _ = observedHeights

        // Escape escalation: the editor tells the host when it ran out of things to do
        // with a semantic action, instead of the host guessing from the responder chain.
        var escalatedActions: [AppKitEditorAction] = []
        controller.onUnhandledAction = { action in
            escalatedActions.append(action)
            return action == .escape
        }
        controller.perform(.undo, makeFirstResponder: false, scrollSelectionIntoView: false)
        _ = escalatedActions

        // Dropping selection is one action, not an escape escalation the host has to count
        // out, and it leaves the responder where the host put it.
        controller.perform(
            .clearSelection,
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )

        // Focus is a first-class contract now: a host observes it, sets it, and reads it
        // back without reaching for a render call.
        controller.setFocused(false)
        var observedFocus: [Bool] = []
        controller.onFocusChange = { observedFocus.append($0) }
        controller.setFocused(true)
        precondition(controller.isFocused)
        controller.setFocused(false)
        precondition(!controller.isFocused)
        precondition(observedFocus == [true, false])

        window.setContentSize(NSSize(width: 720, height: 420))
        controller.view.frame = window.contentView?.bounds ?? .zero
        controller.view.layoutSubtreeIfNeeded()
        precondition(controller.view.bounds.size == NSSize(width: 720, height: 420))

        controller.updateEditorStyle(
            AppKitEditorStyle(
                fontName: style.fontName,
                fontSize: style.fontSize + 1,
                lineHeightMultiple: style.lineHeightMultiple,
                gutterWidth: style.gutterWidth,
                contentHorizontalPadding: style.contentHorizontalPadding,
                blockIndentWidth: style.blockIndentWidth,
                languageIdentifier: style.languageIdentifier
            )
        )
        controller.focus(blockID: blockID, offset: 0)
        controller.replaceActiveText("Updated by the host")
        controller.focus(blockID: blockID, offset: 0)
        _ = controller.perform(
            .insertText("Prefix: "),
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )
        let viewportOwnedActions: [AppKitEditorAction] = [
            .deleteWordBackward,
            .moveWordLeft,
            .moveWordRight,
            .extendCharacterLeft,
            .extendCharacterRight,
            .extendWordLeft,
            .extendWordRight,
        ]
        for action in viewportOwnedActions {
            _ = controller.perform(
                action,
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        }
        // This is intentionally allowed to be a no-op: the public lifecycle still flushes
        // before reading, but this fixture does not claim installed-IME delivery.
        _ = controller.commitActiveComposition()
        let snapshotAfterFlush = controller.documentSnapshot
        precondition(snapshotAfterFlush.epoch == capturedToken?.epoch)
        controller.scrollDocument(to: 0)

        let tokenBeforeReset = capturedToken
        let epochBeforeReset = controller.documentSnapshot.epoch
        let replacementBlockID: BlockID = "fixture-replacement"
        controller.resetDocument(
            blocks: [
                EditorBlockInput(
                    id: replacementBlockID,
                    content: BlockContent(text: "Reset by the host")
                )
            ],
            selection: .caret(blockID: replacementBlockID, offset: 0)
        )

        // The replacement Session restarts revisions at zero, so the epoch is the only
        // thing that tells the host its pending token belongs to a document that is gone.
        let replacementSnapshot = controller.documentSnapshot
        precondition(replacementSnapshot.epoch != epochBeforeReset)
        precondition(replacementSnapshot.revision.rawValue == 0)
        precondition(replacementSnapshot.blocks.map(\.id) == [replacementBlockID])
        precondition(replacementSnapshot.blocks.map(\.content.text) == ["Reset by the host"])
        precondition(tokenBeforeReset?.epoch != replacementSnapshot.epoch)
    }
}
