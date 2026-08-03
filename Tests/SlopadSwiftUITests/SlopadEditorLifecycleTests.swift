import AppKit
import Foundation
import SlopadAppKit
import Testing

@testable import SlopadSwiftUI

@MainActor
@Suite("SwiftUI 호스트 lifecycle 배선")
struct SlopadEditorLifecycleTests {
    // MARK: - Identity Guard

    @Test("같은 id로 document를 다시 만들어도 교체하지 않는다")
    func rebuildingTheSameDocumentIsNotAReplacement() {
        // Given: 선언형 호스트는 body 평가마다 SlopadDocument를 새로 만든다.
        let model = SlopadEditorModel()
        let coordinator = SlopadEditor.Coordinator(model: model)
        let first = SlopadDocument(id: "record-1", blocks: blocks("A"))
        coordinator.appliedDocumentID = first.id

        // When: 값은 다르지만 identity가 같은 인스턴스가 들어온다.
        let rebuilt = SlopadDocument(id: "record-1", blocks: blocks("A"))
        let rebuiltWithDifferentContent = SlopadDocument(id: "record-1", blocks: blocks("B"))

        // Then: 값 비교였다면 여기서 caret·undo stack·IME 조합이 날아간다.
        #expect(!coordinator.shouldReplaceDocument(with: rebuilt))
        #expect(!coordinator.shouldReplaceDocument(with: rebuiltWithDifferentContent))
    }

    @Test("id가 바뀌면 교체한다")
    func changingIdentityReplacesTheDocument() {
        // Given
        let model = SlopadEditorModel()
        let coordinator = SlopadEditor.Coordinator(model: model)
        coordinator.appliedDocumentID = SlopadDocument(id: "record-1", blocks: blocks("A")).id

        // When / Then
        let other = SlopadDocument(id: "record-2", blocks: blocks("A"))
        #expect(coordinator.shouldReplaceDocument(with: other))
    }

    @Test("document가 없으면 교체하지 않는다")
    func absentDocumentIsNotAReplacement() {
        // Given: 호스트 콘텐츠가 아직 로드되지 않은 상태.
        let model = SlopadEditorModel()
        let coordinator = SlopadEditor.Coordinator(model: model)
        coordinator.appliedDocumentID = SlopadDocument(id: "record-1", blocks: blocks("A")).id

        // When / Then
        #expect(!coordinator.shouldReplaceDocument(with: nil))
    }

    @Test("서로 다른 타입의 id는 섞이지 않는다")
    func identitiesOfDifferentTypesDoNotCollide() {
        // Given
        let model = SlopadEditorModel()
        let coordinator = SlopadEditor.Coordinator(model: model)
        coordinator.appliedDocumentID = SlopadDocument(id: 1, blocks: blocks("A")).id

        // When / Then: Int 1과 String "1"은 다른 문서다.
        #expect(coordinator.shouldReplaceDocument(with: SlopadDocument(id: "1", blocks: blocks("A"))))
        #expect(!coordinator.shouldReplaceDocument(with: SlopadDocument(id: 1, blocks: blocks("A"))))
    }

    // MARK: - Committed Change Filtering

    @Test("committed가 아닌 update는 onCommittedChange를 발화시키지 않는다")
    func nonCommittedUpdatesAreFiltered() {
        // Given
        let context = MountedEditor()
        var committedCount = 0
        context.setCommittedChangeAction { committedCount += 1 }

        // When: selection만 움직인다.
        context.controller.perform(
            .moveRight,
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )

        // Then: 이 필터가 없으면 typing 경로에 serialization이 들어간다.
        #expect(committedCount == 0)
    }

    @Test("canonical 변경만 onCommittedChange를 발화시킨다")
    func committedChangesReachTheHost() {
        // Given
        let context = MountedEditor()
        var committedCount = 0
        context.setCommittedChangeAction { committedCount += 1 }

        // When
        context.controller.perform(
            .insertText("!"),
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )

        // Then
        #expect(committedCount == 1)
        #expect(context.model.documentRevision?.rawValue == 1)
    }

    // MARK: - Observable Projection

    @Test("model은 update에서 undo/redo와 epoch을 투영한다")
    func modelProjectsUpdateState() {
        // Given
        let context = MountedEditor()
        #expect(!context.model.canUndo)

        // When
        context.controller.perform(
            .insertText("!"),
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )

        // Then
        #expect(context.model.canUndo)
        #expect(context.model.epoch == context.controller.documentSnapshot.epoch)
    }

    @Test("document 교체 후 세션 단위 상태가 초기화된다")
    func replacementResetsPerSessionState() {
        // Given
        let context = MountedEditor()
        context.controller.perform(
            .insertText("!"),
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )
        let epochBefore = context.model.epoch
        #expect(context.model.documentRevision != nil)
        #expect(context.model.canUndo)

        // When
        context.controller.resetDocument(blocks: blocks("B"))
        context.model.applyDocumentReplacement(epoch: context.controller.documentSnapshot.epoch)

        // Then: 교체된 세션의 revision 0을 이전 세션 것과 헷갈리면 안 된다.
        #expect(context.model.documentRevision == nil)
        #expect(!context.model.canUndo)
        #expect(context.model.epoch != epochBefore)
    }

    @Test("documentSnapshot은 mount 전 nil, mount 후 값이다")
    func snapshotFollowsMounting() {
        // Given
        let model = SlopadEditorModel()
        #expect(model.documentSnapshot == nil)

        // When
        let context = MountedEditor(model: model)

        // Then
        #expect(model.documentSnapshot != nil)
        #expect(model.documentSnapshot?.epoch == context.controller.documentSnapshot.epoch)
    }

    @Test("unmount 후에는 낡은 controller를 읽지 않는다")
    func detachStopsReadingAStaleController() {
        // Given
        let context = MountedEditor()
        #expect(context.model.documentSnapshot != nil)

        // When
        context.coordinator.unbind(controller: context.controller)

        // Then
        #expect(context.model.documentSnapshot == nil)
    }

    // MARK: - Composition Flush

    @Test("commitComposition은 동기다 — 반환 시점에 조합 음절이 문서에 있다")
    func compositionFlushIsSynchronous() throws {
        // Given: 이걸 틀리면 IME 마지막 음절이 조용히 유실된다.
        let context = MountedEditor()
        context.controller.setMarkedTextFromNativeSurface(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(context.controller.hasActiveNativeMarkedText)

        // When
        context.model.commitComposition()

        // Then: await 없이 곧바로 읽는다.
        let snapshot = try #require(context.model.documentSnapshot)
        #expect(snapshot.blocks.first?.content.text.contains("한") == true)
    }

    // MARK: - Height and Focus

    @Test("content height가 model로 흐른다")
    func contentHeightReachesTheModel() {
        // Given
        let context = MountedEditor()

        // When
        context.controller.onContentHeightChange?(240)

        // Then
        #expect(context.model.contentHeight == 240)
    }

    @Test("focus 변경이 model로 흐른다")
    func focusReachesTheModel() {
        // Given
        let context = MountedEditor()
        #expect(!context.model.isFocused)

        // When
        context.controller.onFocusChange?(true)

        // Then
        #expect(context.model.isFocused)
    }
}

// MARK: - Support

private func blocks(_ text: String) -> [EditorBlockInput] {
    [EditorBlockInput(id: "block", content: BlockContent(text: text))]
}

/// A coordinator bound to a real controller, which is what `makeNSViewController` produces.
@MainActor
private final class MountedEditor {
    let model: SlopadEditorModel
    let controller: AppKitEditorViewController
    let coordinator: SlopadEditor.Coordinator
    let window: NSWindow
    private var editor: SlopadEditor

    init(model: SlopadEditorModel = SlopadEditorModel()) {
        self.model = model
        let document = SlopadDocument(id: "record-1", blocks: blocks("A"))
        controller = AppKitEditorViewController(
            blocks: document.blocks,
            selection: .caret(blockID: "block", offset: 1)
        )
        // A real mount lays the editor out, which is what gives the native input surface an
        // active block to compose into.
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        editor = SlopadEditor(model: model, document: document)
        coordinator = SlopadEditor.Coordinator(model: model)
        coordinator.appliedDocumentID = document.id
        coordinator.bind(controller: controller, editor: editor)
        model.attach(controller)
    }

    func setCommittedChangeAction(_ action: @escaping () -> Void) {
        editor = editor.onCommittedChange(action)
        coordinator.editor = editor
    }
}
