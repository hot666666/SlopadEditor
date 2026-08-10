import AppKit
import SlopadSwiftUI
import SwiftUI

@MainActor
private struct HostRoot: View {
    let editor: SlopadEditor?
    let model: SlopadEditorModel

    @FocusState private var isEditing: Bool

    @ViewBuilder
    var body: some View {
        if let editor {
            editor
                .focused($isEditing)
                .onChange(of: model.isFocused) { _, isFocused in
                    guard !isFocused else { return }
                    model.clearSelection()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyView()
        }
    }
}

@main
@MainActor
private struct DownstreamSwiftUIHost {
    static func main() {
        _ = NSApplication.shared

        let initialBlockID: BlockID = "swiftui-initial"
        let replacementBlockID: BlockID = "swiftui-replacement"
        let model = SlopadEditorModel()
        var committedChangeCount = 0
        let initialDocument = SlopadDocument(
            id: "record-1",
            blocks: [
                EditorBlockInput(
                    id: initialBlockID,
                    content: BlockContent(text: "Initial SwiftUI document")
                )
            ]
        )

        func editor(document: SlopadDocument) -> SlopadEditor {
            SlopadEditor(model: model, document: document)
                .editorStyle(AppKitEditorStyle())
                .onCommittedChange { committedChangeCount += 1 }
                .onUnhandledAction { $0 == .escape }
        }

        var hostingController: NSHostingController<HostRoot>? = NSHostingController(
            rootView: HostRoot(editor: editor(document: initialDocument), model: model)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.contentViewController = hostingController
        window.makeKeyAndOrderFront(nil)
        hostingController?.view.frame = window.contentView?.bounds ?? .zero
        hostingController?.view.layoutSubtreeIfNeeded()

        waitUntil("SwiftUI editor did not mount") {
            model.documentSnapshot?.blocks.map(\.id) == [initialBlockID]
        }
        let initialEpoch = require(model.epoch, "Mounted model must publish an epoch")
        precondition(
            model.documentSnapshot?.blocks.first?.content.text == "Initial SwiftUI document"
        )

        // A semantic action enters only through the public observable model after mount.
        precondition(model.perform(.insertText(" edited")))
        waitUntil("Committed SwiftUI edit was not observed") {
            committedChangeCount == 1 && model.documentRevision?.rawValue == 1
        }
        precondition(
            model.documentSnapshot?.blocks.first?.content.text
                == "Initial SwiftUI document edited"
        )

        model.setFocused(true)
        waitUntil("SwiftUI focus did not reach the mounted editor") { model.isFocused }
        model.setFocused(false)
        waitUntil("SwiftUI blur did not reach the mounted editor") { !model.isFocused }

        window.setContentSize(NSSize(width: 720, height: 420))
        hostingController?.view.frame = window.contentView?.bounds ?? .zero
        hostingController?.view.layoutSubtreeIfNeeded()
        precondition(hostingController?.view.bounds.size == NSSize(width: 720, height: 420))

        // Flush first, then read. This can be a no-op because installed IME delivery is
        // outside this public lifecycle gate.
        model.commitComposition()
        let snapshotAfterFlush = require(
            model.documentSnapshot,
            "Flush-before-read must leave a committed snapshot"
        )
        precondition(snapshotAfterFlush.epoch == initialEpoch)
        precondition(snapshotAfterFlush.revision.rawValue == 1)

        let replacementDocument = SlopadDocument(
            id: "record-2",
            blocks: [
                EditorBlockInput(
                    id: replacementBlockID,
                    content: BlockContent(text: "Replacement SwiftUI document")
                )
            ]
        )
        hostingController?.rootView = HostRoot(
            editor: editor(document: replacementDocument),
            model: model
        )
        hostingController?.view.layoutSubtreeIfNeeded()
        waitUntil("SwiftUI document identity did not replace the mounted Session") {
            guard let snapshot = model.documentSnapshot else { return false }
            return model.epoch != initialEpoch
                && snapshot.epoch == model.epoch
                && snapshot.revision.rawValue == 0
                && snapshot.blocks.map(\.id) == [replacementBlockID]
                && snapshot.blocks.map(\.content.text) == ["Replacement SwiftUI document"]
        }

        // Removing the representable from the host tree must invoke dismantling, so the
        // public model can no longer read a stale controller.
        model.setFocused(false)
        hostingController?.rootView = HostRoot(editor: nil, model: model)
        hostingController?.view.layoutSubtreeIfNeeded()
        waitUntil("SwiftUI editor did not detach during teardown") {
            model.documentSnapshot == nil
        }

        window.orderOut(nil)
        window.contentViewController = nil
        hostingController = nil
        window.close()
    }

    private static func waitUntil(
        _ failureMessage: @autoclosure () -> String,
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date(timeIntervalSinceNow: 0.01)))
        }
        precondition(condition(), failureMessage())
    }

    private static func require<Value>(_ value: Value?, _ message: String) -> Value {
        guard let value else { preconditionFailure(message) }
        return value
    }
}
