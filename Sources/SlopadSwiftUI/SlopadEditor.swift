import SlopadAppKit
import SwiftUI

// MARK: - SlopadEditor

/// A SwiftUI view that embeds the editor as an ordinary subview.
///
/// It exists to own the lifecycle wiring every SwiftUI host would otherwise re-derive, and
/// gets each of those wrong in a way that is silent:
///
/// - **Identity guard.** A declarative host re-evaluates its body constantly. Pushing the
///   document on every pass destroys the caret, the undo stack, and live IME composition.
/// - **Committed-change filtering.** `onUpdate` fires for selection, layout and composition
///   too. A host that treats every update as a change puts serialization on the typing path.
/// - **Epoch staleness.** Revisions restart at zero when the document is replaced, so a
///   host holding a revision can persist into the wrong document.
/// - **Composition flush before persisting.** Reading the document mid-composition silently
///   drops the syllable being typed.
///
/// It stays deliberately thin: lifecycle wiring and observable projection only. Anything
/// that decides what an edit *means* belongs in `EditorSession`.
@MainActor
public struct SlopadEditor: NSViewControllerRepresentable {
    // MARK: - Configuration

    private let model: SlopadEditorModel
    private let document: SlopadDocument?
    private var style = AppKitEditorStyle()
    private var focusBinding: FocusState<Bool>.Binding?
    private var committedChangeAction: (() -> Void)?
    private var unhandledActionHandler: ((AppKitEditorAction) -> Bool)?

    /// - Parameters:
    ///   - model: The observable projection to drive. Hold it in `@State`.
    ///   - document: The document to show. A `nil` document mounts an empty editor, so a
    ///     host can render before its content has loaded.
    public init(model: SlopadEditorModel, document: SlopadDocument?) {
        self.model = model
        self.document = document
    }

    // MARK: - Modifiers

    /// Runs when the canonical document actually changed.
    ///
    /// Selection, scrolling, layout and live composition updates do not call it, which is
    /// what keeps a host's save scheduling off the typing path.
    public func onCommittedChange(_ action: @escaping () -> Void) -> SlopadEditor {
        var copy = self
        copy.committedChangeAction = action
        return copy
    }

    /// Runs when the engine refused a semantic action. Return `true` if the host consumed
    /// it, `false` to leave the editor's default handling in place.
    public func onUnhandledAction(
        _ action: @escaping (AppKitEditorAction) -> Bool
    ) -> SlopadEditor {
        var copy = self
        copy.unhandledActionHandler = action
        return copy
    }

    /// Binds editor focus to a `@FocusState` value, in both directions.
    ///
    /// This shadows SwiftUI's `focused(_:)` on purpose: SwiftUI's focus system does not
    /// reach into an AppKit first responder, so the two sides are synchronized explicitly.
    public func focused(_ binding: FocusState<Bool>.Binding) -> SlopadEditor {
        var copy = self
        copy.focusBinding = binding
        return copy
    }

    /// Sets the text system configuration.
    public func editorStyle(_ style: AppKitEditorStyle) -> SlopadEditor {
        var copy = self
        copy.style = style
        return copy
    }

    // MARK: - NSViewControllerRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    public func makeNSViewController(context: Context) -> AppKitEditorViewController {
        let controller = AppKitEditorViewController(
            blocks: document?.blocks ?? Self.emptyDocumentBlocks,
            style: style
        )
        context.coordinator.appliedDocumentID = document?.id
        context.coordinator.bind(controller: controller, editor: self)
        model.attach(controller)
        return controller
    }

    public func updateNSViewController(
        _ controller: AppKitEditorViewController,
        context: Context
    ) {
        // Refresh the captured closures so callbacks always run the newest host state,
        // without re-registering them on the controller.
        context.coordinator.editor = self

        if style != controller.editorStyle {
            controller.updateEditorStyle(style)
        }

        // The identity guard. Everything above ran on an ordinary re-render; only an actual
        // identity change is allowed past here.
        if let document, context.coordinator.shouldReplaceDocument(with: document) {
            context.coordinator.appliedDocumentID = document.id
            controller.resetDocument(blocks: document.blocks)
            model.applyDocumentReplacement(epoch: controller.documentSnapshot.epoch)
        }

        if let focusBinding, focusBinding.wrappedValue != controller.isFocused {
            controller.setFocused(focusBinding.wrappedValue)
        }
    }

    public static func dismantleNSViewController(
        _ controller: AppKitEditorViewController,
        coordinator: Coordinator
    ) {
        coordinator.unbind(controller: controller)
    }

    /// A document must have at least one block, so an unloaded host renders one empty
    /// paragraph rather than an invalid document.
    private static var emptyDocumentBlocks: [EditorBlockInput] {
        [EditorBlockInput(id: "slopad.swiftui.placeholder", content: BlockContent(text: ""))]
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator {
        /// The identity currently mounted. Comparing against it is the identity guard.
        var appliedDocumentID: AnyHashable?
        /// The most recent view value, so callbacks registered once still see fresh state.
        var editor: SlopadEditor?
        private let model: SlopadEditorModel

        init(model: SlopadEditorModel) {
            self.model = model
        }

        /// Decides whether an incoming document is a different document.
        ///
        /// Compares identity, never contents. A host rebuilds its `SlopadDocument` on every
        /// body evaluation, so a value comparison would report a replacement on every pass
        /// and take the caret, the undo stack and any live composition with it.
        func shouldReplaceDocument(with document: SlopadDocument?) -> Bool {
            guard let document else { return false }
            return appliedDocumentID != document.id
        }

        func bind(controller: AppKitEditorViewController, editor: SlopadEditor) {
            self.editor = editor

            controller.onUpdate = { [weak self] update in
                guard let self else { return }
                model.apply(update)
                guard update.committedDocumentRevision != nil else { return }
                self.editor?.committedChangeAction?()
            }

            controller.onContentHeightChange = { [weak self] height in
                self?.model.applyContentHeight(height)
            }

            controller.onFocusChange = { [weak self] isFocused in
                guard let self else { return }
                model.applyFocus(isFocused)
                // Report focus the host did not initiate — a click, or another view taking
                // it — so the binding does not desynchronize.
                if self.editor?.focusBinding?.wrappedValue != isFocused {
                    self.editor?.focusBinding?.wrappedValue = isFocused
                }
            }

            controller.onUnhandledAction = { [weak self] action in
                self?.editor?.unhandledActionHandler?(action) ?? false
            }
        }

        func unbind(controller: AppKitEditorViewController) {
            controller.onUpdate = nil
            controller.onContentHeightChange = nil
            controller.onFocusChange = nil
            controller.onUnhandledAction = nil
            editor = nil
            model.detach()
        }
    }
}
