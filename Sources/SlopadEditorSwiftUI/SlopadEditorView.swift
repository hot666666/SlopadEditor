import SlopadEditorAppKit
import SwiftUI

// MARK: - SlopadEditorView

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
public struct SlopadEditorView: NSViewControllerRepresentable {
    // MARK: - Configuration

    private let model: SlopadEditorViewModel
    private let document: SlopadEditorDocument?
    private var style = AppKitEditorStyle()
    private var focusBinding: FocusState<Bool>.Binding?
    private var committedChangeAction: (() -> Void)?
    private var unhandledActionHandler: ((AppKitEditorAction) -> Bool)?

    /// - Parameters:
    ///   - model: The observable projection to drive. Hold it in `@State`.
    ///   - document: The document to show. A `nil` document mounts an empty editor, so a
    ///     host can render before its content has loaded.
    public init(model: SlopadEditorViewModel, document: SlopadEditorDocument?) {
        self.model = model
        self.document = document
    }

    // MARK: - Modifiers

    /// Runs when the canonical document actually changed.
    ///
    /// Selection, scrolling, layout and live composition updates do not call it, which is
    /// what keeps a host's save scheduling off the typing path.
    public func onCommittedChange(_ action: @escaping () -> Void) -> SlopadEditorView {
        var copy = self
        copy.committedChangeAction = action
        return copy
    }

    /// Runs when the engine refused a semantic action. Return `true` if the host consumed
    /// it, `false` to leave the editor's default handling in place.
    public func onUnhandledAction(
        _ action: @escaping (AppKitEditorAction) -> Bool
    ) -> SlopadEditorView {
        var copy = self
        copy.unhandledActionHandler = action
        return copy
    }

    /// Binds editor focus to a `@FocusState` value, in both directions.
    ///
    /// This shadows SwiftUI's `focused(_:)` on purpose: SwiftUI's focus system does not
    /// reach into an AppKit first responder, so the two sides are synchronized explicitly.
    public func focused(_ binding: FocusState<Bool>.Binding) -> SlopadEditorView {
        var copy = self
        copy.focusBinding = binding
        return copy
    }

    /// Sets the text system configuration.
    public func editorStyle(_ style: AppKitEditorStyle) -> SlopadEditorView {
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
        var editor: SlopadEditorView?
        private let model: SlopadEditorViewModel

        init(model: SlopadEditorViewModel) {
            self.model = model
        }

        /// Decides whether an incoming document is a different document.
        ///
        /// Compares identity, never contents. A host rebuilds its `SlopadEditorDocument` on every
        /// body evaluation, so a value comparison would report a replacement on every pass
        /// and take the caret, the undo stack and any live composition with it.
        func shouldReplaceDocument(with document: SlopadEditorDocument?) -> Bool {
            guard let document else { return false }
            return appliedDocumentID != document.id
        }

        func bind(controller: AppKitEditorViewController, editor: SlopadEditorView) {
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

// MARK: - Preview

#Preview("SlopadEditorView Save/Interaction PoC") {
	SlopadEditorPoC()
		.frame(width: 680, height: 500)
}

private struct SlopadEditorPoC: View {
	@State private var editorModel = SlopadEditorViewModel()
	@State private var document = SlopadEditorDocument(
		id: "slopad.editor.poc",
		blocks: [
			EditorBlockInput(
				id: "p-1",
				kind: .heading(level: .h1),
				content: BlockContent(text: "SlopadEditorView SwiftUI Preview PoC")
			),
			EditorBlockInput(
				id: "p-2",
				content: BlockContent(text: "이 영역에서 직접 편집해 보세요. 타이핑/삭제/드래그 동작이 동작합니다.")
			),
			EditorBlockInput(
				id: "p-3",
				kind: .quote,
				content: BlockContent(text: "커밋된 수정은 onCommittedChange에서 print로 출력됩니다.")
			),
			EditorBlockInput(
				id: "p-4",
				kind: .todo(isChecked: false),
				content: BlockContent(text: "프리뷰에서도 저장 동작을 확인한다")
			),
		]
	)

	private var revisionLabel: String {
		editorModel.documentSnapshot?.revision.rawValue.description
			?? editorModel.documentRevision?.rawValue.description
			?? "nil"
	}
	private var selectionLabel: String {
		String(describing: editorModel.isFocused)
	}
	private var editorSessionEpochLabel: String {
		if editorModel.epoch == nil { return "nil" }
		return "active"
	}

	/// 에디터 바깥을 눌렀을 때의 선택 해제.
	///
	/// `escape`를 두 번 보내 흉내내지 않는다. escape는 한 번에 한 단계(caret/text -> blocks
	/// -> inactive)만 올라가므로 필요한 횟수가 현재 선택 모드에 따라 달라지고, 기본 action 경로는
	/// 응답자까지 가져온다. `clearSelection()`은 한 번에 해제하고 포커스는 건드리지 않는다.
	private func clearSelectedBlock() {
		editorModel.clearSelection()
	}

	var body: some View {
		VStack(spacing: 10) {
			VStack(alignment: .leading, spacing: 4) {
				SlopadEditorView(
					model: editorModel,
					document: document
				)
				.onCommittedChange {
					editorModel.commitComposition()
					guard let snapshot = editorModel.documentSnapshot else {
						print("[SlopadEditorView PoC] save skipped: snapshot is nil")
						return
					}
					let summary = snapshot.blocks.enumerated().map { index, block in
						"\(index + 1). \(block.kind) - \(block.id) - \(block.content.text)"
					}
					print("[SlopadEditorView PoC] SAVE revision=\(snapshot.revision.rawValue), epoch=\(snapshot.epoch)")
					print("[SlopadEditorView PoC] blocks:")
					for line in summary {
						print("  \(line)")
					}
				}
				.onUnhandledAction { action in
					print("[SlopadEditorView PoC] unhandledAction = \(String(describing: action))")
					return false
				}
				.onChange(of: editorModel.documentRevision) { _, revision in
					print("[SlopadEditorView PoC] revision changed => \(revision?.rawValue.description ?? "nil")")
				}
				// firstResponder를 다른 뷰에 뺏긴 경우. 에디터는 포커스 변화를 보고만 하고,
				// 남은 선택을 어떻게 할지는 호스트 정책이다. 이 PoC는 해제하는 쪽을 택한다.
				.onChange(of: editorModel.isFocused) { _, isFocused in
					guard !isFocused else { return }
					editorModel.clearSelection()
				}
				.frame(maxWidth: .infinity, minHeight: 220, maxHeight: 280, alignment: .top)
			}
			.accessibilityLabel("SlopadEditorView Preview")
			.background(.thinMaterial)
			.clipShape(RoundedRectangle(cornerRadius: 8))

			VStack(alignment: .leading, spacing: 4) {
				Text("Revision: \(revisionLabel)")
				Text("Epoch: \(editorSessionEpochLabel)")
				Text("Undo 가능: \(editorModel.canUndo.description) / Redo 가능: \(editorModel.canRedo.description)")
				Text("Composition 중: \(editorModel.isComposing.description)")
				Text("선택(블록/텍스트): \(selectionLabel)")
				Text("Height: \(editorModel.contentHeight)")
			}
			.font(.caption)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(8)
			.background(.regularMaterial)
			.cornerRadius(6)

			RoundedRectangle(cornerRadius: 8)
				.fill(.gray.opacity(0.15))
				.frame(maxWidth: .infinity, minHeight: 54)
				.overlay(alignment: .center) {
					Text("여기를 클릭하면 에디터 외부 터치로 블록 선택이 해제됩니다")
						.font(.caption)
				}
				.contentShape(Rectangle())
				.onTapGesture {
					clearSelectedBlock()
				}

			HStack {
				Button("샘플 재적재(문서 교체)") {
					document = SlopadEditorDocument(
						id: UUID(),
						blocks: [
							EditorBlockInput(
								id: "p-1",
								kind: .heading(level: .h2),
								content: BlockContent(text: "교체된 샘플 문서")
							),
							EditorBlockInput(
								id: "p-2",
								content: BlockContent(text: "이 버튼을 누르면 문서가 교체되어 리프레시가 일어납니다.")
							),
						]
					)
				}
			}
			.buttonStyle(.bordered)
		}
		.padding()
	}
}
