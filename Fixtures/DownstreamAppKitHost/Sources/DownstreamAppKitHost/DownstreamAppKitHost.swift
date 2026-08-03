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

        do {
            try exercisePublicHostContract(controller, blockID: blockID, style: style)
        } catch {
            fatalError("Public SlopadAppKit contract failed: \(error)")
        }
    }

    private static func exercisePublicHostContract(
        _ controller: AppKitEditorViewController,
        blockID: BlockID,
        style: AppKitEditorStyle
    ) throws {
        controller.onSnapshotChanged = { _ in }
        controller.onUpdate = { [weak controller] update in
            guard let revision = update.committedDocumentRevision else { return }
            let documentSnapshot = controller?.documentSnapshot
            _ = documentSnapshot?.revision == revision
            _ = documentSnapshot?.blocks
        }
        controller.blockChromeRenderer = HostChromeRenderer()
        _ = controller.editorStyle == style
        _ = controller.snapshot
        _ = controller.documentSnapshot

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
        precondition(assistantUpdate?.committedDocumentRevision?.rawValue == 1)
        let noOpContext = try controller.documentContextSnapshot()
        let noOpUpdate = try controller.applyDocumentPatch(
            EditorDocumentPatch(
                source: noOpContext.source,
                replacementBlocks: noOpContext.document.blocks,
                selectionAfter: noOpContext.selection
            )
        )
        precondition(noOpUpdate == nil)

        controller.renderAndSyncSurface(makeFirstResponder: false)
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
        _ = controller.commitActiveComposition()
        controller.scrollDocument(to: 0)
        controller.resetDocument(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: "Reset by the host")
                )
            ],
            selection: .caret(blockID: blockID, offset: 0)
        )
    }
}
