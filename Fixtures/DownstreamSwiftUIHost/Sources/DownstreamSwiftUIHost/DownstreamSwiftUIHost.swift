import AppKit
import SlopadSwiftUI
import SwiftUI

// MARK: - Host Record

/// The host's own storage model. Slopad never sees this type, and never sees the string
/// inside it: turning it into blocks is the host codec's job.
private struct Record: Identifiable {
    let id: String
    let body: String
}

/// The host codec. Its existence in the fixture and its absence from the Slopad API is the
/// `[EditorBlockInput]`-only invariant, checked by compilation.
private enum HostCodec {
    static func decode(_ body: String) -> [EditorBlockInput] {
        body.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in
                EditorBlockInput(
                    id: BlockID("line-\(index)"),
                    content: BlockContent(text: String(line))
                )
            }
    }

    static func encode(_ blocks: [EditorBlockInput]) -> String {
        blocks.map(\.content.text).joined(separator: "\n")
    }
}

// MARK: - Host View

/// The complete embedding surface a SwiftUI host writes.
///
/// Everything absent here is the point: no identity guard, no generation counter, no
/// composition endpoint wiring, no render call to move focus, no snapshot subscription to
/// learn the height.
private struct HostView: View {
    let record: Record

    @State private var editor = SlopadEditorModel()
    @State private var document: SlopadDocument?
    @FocusState private var isEditing: Bool

    var body: some View {
        SlopadEditor(model: editor, document: document)
            .focused($isEditing)
            .onCommittedChange { scheduleSave() }
            .onUnhandledAction { action in
                guard action == .escape else { return false }
                isEditing = false
                return true
            }
            // Another view in the window took the responder. What remains selected is host
            // policy; dropping it takes one call and does not pull focus back.
            .onChange(of: editor.isFocused) { _, isFocused in
                guard !isFocused else { return }
                editor.clearSelection()
            }
            .frame(height: max(editor.contentHeight, 1))
            .task(id: record.id) {
                document = SlopadDocument(
                    id: record.id,
                    blocks: HostCodec.decode(record.body)
                )
            }
    }

    private func scheduleSave() {
        // A real host debounces here. What matters for the contract is that the token it
        // captures is made of public values.
        _ = (editor.epoch, editor.documentRevision)
    }
}

// MARK: - Contract Exercise

@main
@MainActor
private struct DownstreamSwiftUIHost {
    static func main() {
        exerciseObservableSurface()
        exerciseViewComposition()
        exercisePersistenceHandshake()
        exerciseHostOwnedCodec()
    }

    /// Every value a host binds to has to be readable without reaching into the adapter.
    private static func exerciseObservableSurface() {
        let model = SlopadEditorModel()
        let _: EditorSessionEpoch? = model.epoch
        let _: EditorDocumentRevision? = model.documentRevision
        let _: Bool = model.canUndo
        let _: Bool = model.canRedo
        let _: Bool = model.isComposing
        let _: Bool = model.isFocused
        let _: Double = model.contentHeight
        let _: EditorDocumentSnapshot? = model.documentSnapshot
        model.commitComposition()
        model.setFocused(false)
        _ = model.clearSelection()
        _ = model.perform(.insertText("host toolbar button"))
    }

    /// The view has to compose with the modifiers a host actually writes.
    private static func exerciseViewComposition() {
        let record = Record(id: "record-1", body: "First line\nSecond line")
        let hostView = HostView(record: record)
        let controller = NSHostingController(rootView: hostView)
        controller.view.setFrameSize(NSSize(width: 480, height: 320))
        controller.view.layoutSubtreeIfNeeded()
    }

    /// The sequence that loses the last IME syllable when a host gets it wrong.
    private static func exercisePersistenceHandshake() {
        let model = SlopadEditorModel()
        let record = Record(id: "record-2", body: "Persisted line")
        let document = SlopadDocument(id: record.id, blocks: HostCodec.decode(record.body))

        let controller = NSHostingController(
            rootView: SlopadEditor(model: model, document: document)
                .frame(width: 480, height: 320)
        )
        controller.view.layoutSubtreeIfNeeded()

        let capturedEpoch = model.epoch

        // Flush composition first, then read. The other order silently drops the syllable
        // being composed.
        model.commitComposition()
        guard let snapshot = model.documentSnapshot else {
            fatalError("A mounted editor must expose a document snapshot")
        }
        precondition(snapshot.epoch == capturedEpoch)
        precondition(!snapshot.blocks.isEmpty)
        _ = HostCodec.encode(snapshot.blocks)
    }

    /// Encoding and decoding stay on the host side of the boundary.
    private static func exerciseHostOwnedCodec() {
        let blocks = HostCodec.decode("alpha\nbeta")
        precondition(blocks.count == 2)
        precondition(HostCodec.encode(blocks) == "alpha\nbeta")

        // Identity is a host-chosen value, not a Slopad type.
        let document = SlopadDocument(id: UUID(), blocks: blocks)
        precondition(document.blocks.count == 2)
    }
}
