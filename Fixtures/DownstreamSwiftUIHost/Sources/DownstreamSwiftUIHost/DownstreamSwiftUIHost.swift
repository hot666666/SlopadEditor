import AppKit
import SlopadEditorSwiftUI
import SwiftUI

/// Counts host body evaluations so a lifecycle step can wait for SwiftUI's update pass to
/// actually run before asserting that the mounted Session was left alone. A fixed sleep
/// would let every such assertion pass vacuously on a loaded machine.
@MainActor
private final class BodyEvaluationCounter {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
private struct HostRoot: View {
    let editor: SlopadEditorView?
    let model: SlopadEditorViewModel
    let bodyEvaluations: BodyEvaluationCounter

    @FocusState private var isEditing: Bool

    @ViewBuilder
    var body: some View {
        let _ = bodyEvaluations.record()
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
        let model = SlopadEditorViewModel()
        var committedChangeCount = 0
        var callbackSnapshotRevisions: [UInt64] = []
        let bodyEvaluations = BodyEvaluationCounter()
        let initialDocument = SlopadEditorDocument(
            id: "record-1",
            blocks: [
                EditorBlockInput(
                    id: initialBlockID,
                    content: BlockContent(text: "Initial SwiftUI document")
                )
            ]
        )

        func editor(document: SlopadEditorDocument) -> SlopadEditorView {
            SlopadEditorView(model: model, document: document)
                .editorStyle(AppKitEditorStyle())
                .onCommittedChange {
                    committedChangeCount += 1
                    let snapshot = require(
                        model.documentSnapshot,
                        "Committed callback must observe its complete snapshot"
                    )
                    precondition(snapshot.revision == model.documentRevision)
                    callbackSnapshotRevisions.append(snapshot.revision.rawValue)
                }
                .onUnhandledAction { $0 == .escape }
        }

        var hostingController: NSHostingController<HostRoot>? = NSHostingController(
            rootView: HostRoot(
                editor: editor(document: initialDocument),
                model: model,
                bodyEvaluations: bodyEvaluations
            )
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

        // A host-owned toolbar can send existing public actions without reading a public
        // command-state projection. The formatting edit remains one transaction and one
        // undo step through the same observable lifecycle surface.
        precondition(model.perform(.selectAll))
        precondition(model.perform(.toggleInlineStyle(.strong)))
        waitUntil("SwiftUI formatting command was not observed") {
            committedChangeCount == 1 && model.documentRevision?.rawValue == 1
        }
        precondition(callbackSnapshotRevisions == [1])
        precondition(
            model.documentSnapshot?.blocks.first?.content.marks == [
                .init(kind: .strong, range: TextRange(0, 24))
            ]
        )
        precondition(model.perform(.undo))
        waitUntil("SwiftUI formatting undo was not observed") {
            committedChangeCount == 2
                && model.documentRevision?.rawValue == 2
                && !model.canUndo
                && model.canRedo
        }
        precondition(callbackSnapshotRevisions == [1, 2])
        precondition(model.documentSnapshot?.blocks.first?.content.marks.isEmpty == true)

        // A semantic action enters only through the public observable model after mount.
        precondition(model.perform(.moveRight))
        precondition(model.perform(.insertText(" edited")))
        waitUntil("Committed SwiftUI edit was not observed") {
            committedChangeCount == 3 && model.documentRevision?.rawValue == 3
        }
        precondition(callbackSnapshotRevisions == [1, 2, 3])
        precondition(
            model.documentSnapshot?.blocks.first?.content.text
                == "Initial SwiftUI document edited"
        )

        // Re-evaluating the same host document identity with stale input blocks must not
        // replace the mounted Session, lose the edit, or reset its undo stack.
        let stateBeforeSameIdentityUpdate = (
            epoch: model.epoch,
            revision: model.documentRevision,
            blocks: model.documentSnapshot?.blocks,
            canUndo: model.canUndo
        )
        let staleSameIdentityDocument = SlopadEditorDocument(
            id: "record-1",
            blocks: [
                EditorBlockInput(
                    id: initialBlockID,
                    content: BlockContent(text: "Stale host re-evaluation")
                )
            ]
        )
        let evaluationsBeforeSameIdentityUpdate = bodyEvaluations.count
        hostingController?.rootView = HostRoot(
            editor: editor(document: staleSameIdentityDocument),
            model: model,
            bodyEvaluations: bodyEvaluations
        )
        hostingController?.view.layoutSubtreeIfNeeded()
        // Wait for the update pass to actually run. The assertions below are all negative,
        // so without a positive signal that SwiftUI re-evaluated the host, a slow machine
        // would satisfy every one of them by never having updated at all.
        waitUntil("SwiftUI did not re-evaluate the host for the same document identity") {
            bodyEvaluations.count > evaluationsBeforeSameIdentityUpdate
        }
        precondition(model.epoch == stateBeforeSameIdentityUpdate.epoch)
        precondition(model.documentRevision == stateBeforeSameIdentityUpdate.revision)
        precondition(model.documentSnapshot?.blocks == stateBeforeSameIdentityUpdate.blocks)
        precondition(model.canUndo == stateBeforeSameIdentityUpdate.canUndo)
        precondition(committedChangeCount == 3)
        precondition(callbackSnapshotRevisions == [1, 2, 3])

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
        precondition(snapshotAfterFlush.revision.rawValue == 3)

        let replacementDocument = SlopadEditorDocument(
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
            model: model,
            bodyEvaluations: bodyEvaluations
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
        hostingController?.rootView = HostRoot(
            editor: nil,
            model: model,
            bodyEvaluations: bodyEvaluations
        )
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
