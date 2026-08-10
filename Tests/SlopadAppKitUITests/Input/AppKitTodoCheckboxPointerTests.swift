import AppKit
import Testing

@testable import SlopadAppKitUI
@testable import SlopadEngine

@MainActor
@Suite("AppKit todo checkbox pointer control")
struct AppKitTodoCheckboxPointerTests {
    @Test("NSWindow checkbox down-up inside는 clicked todo만 toggle하고 selection을 보존한다")
    func givenTodoCheckbox_whenPointerReleasesInside_thenOneToggleAndUndoRedoOccur() throws {
        // Given
        let text: BlockID = "text"
        let todo: BlockID = "todo"
        let other: BlockID = "other"
        let originalSelection = EditorSelection.text(
            TextSelection(
                anchor: TextPosition(blockID: text, offset: 0),
                focus: TextPosition(blockID: text, offset: 4)
            )
        )
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(id: text, content: .init(text: "Text")),
                EditorBlockInput(id: "spacer-1", content: .init(text: "Spacer")),
                EditorBlockInput(id: "spacer-2", content: .init(text: "Spacer")),
                EditorBlockInput(id: "spacer-3", content: .init(text: "Spacer")),
                EditorBlockInput(id: "spacer-4", content: .init(text: "Spacer")),
                EditorBlockInput(
                    id: todo, kind: .todo(isChecked: false), content: .init(text: "A")),
                EditorBlockInput(
                    id: other, kind: .todo(isChecked: false), content: .init(text: "B")),
            ],
            selection: originalSelection,
            focusOnAppear: false
        )
        let fixture = try mounted(controller)
        defer { fixture.close() }
        let checkbox = try #require(controller.todoCheckboxHitRect(blockID: todo))
        var updates: [EditorUpdate] = []
        controller.onUpdate = { updates.append($0) }

        // When
        try send(.leftMouseDown, at: checkbox.center, fixture: fixture)
        try send(.leftMouseUp, at: checkbox.center, fixture: fixture)

        // Then
        #expect(controller.todoState(blockID: todo) == .on)
        #expect(controller.todoState(blockID: other) == .off)
        #expect(controller.snapshot?.selection == originalSelection)
        #expect(updates.count == 1)
        #expect(updates.first?.committedDocumentRevision?.rawValue == 1)
        #expect(controller.snapshot?.history.canUndo == true)
        _ = try #require(controller.perform(.undo, makeFirstResponder: false))
        #expect(controller.todoState(blockID: todo) == .off)
        #expect(controller.snapshot?.history.canUndo == false)
        #expect(controller.snapshot?.history.canRedo == true)
        #expect(controller.perform(.undo, makeFirstResponder: false) == nil)
        _ = try #require(controller.perform(.redo, makeFirstResponder: false))
        #expect(controller.todoState(blockID: todo) == .on)
        #expect(updates.compactMap { $0.committedDocumentRevision?.rawValue } == [1, 2, 3])
    }

    @Test("marked text 중 다른 todo checkbox click은 조합과 canonical selection을 보존한다")
    func givenLiveComposition_whenClickingAnotherTodoCheckbox_thenOnlyTodoTransactionCommits()
        throws
    {
        // Given
        let text: BlockID = "text"
        let todo: BlockID = "todo"
        let originalSelection = EditorSelection.text(
            TextSelection(
                anchor: TextPosition(blockID: text, offset: 0),
                focus: TextPosition(blockID: text, offset: 4)
            )
        )
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(id: text, content: .init(text: "Text")),
                EditorBlockInput(id: "spacer-1", content: .init(text: "Spacer")),
                EditorBlockInput(id: "spacer-2", content: .init(text: "Spacer")),
                EditorBlockInput(id: "spacer-3", content: .init(text: "Spacer")),
                EditorBlockInput(id: "spacer-4", content: .init(text: "Spacer")),
                EditorBlockInput(
                    id: todo, kind: .todo(isChecked: false), content: .init(text: "Todo")),
            ],
            selection: originalSelection,
            focusOnAppear: false
        )
        let fixture = try mounted(controller)
        defer { fixture.close() }
        fixture.window.makeFirstResponder(controller.canvasView)
        controller.setMarkedTextFromNativeSurface(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let checkbox = try #require(controller.todoCheckboxHitRect(blockID: todo))
        let compositionBeforeClick = try #require(controller.snapshot?.composition)
        let markedRangeBeforeClick = controller.activeNativeMarkedRange
        let markedReplacementRangeBeforeClick = controller.activeNativeMarkedReplacementRange
        let markedDocumentTextBeforeClick = controller.activeNativeMarkedDocumentText
        let nativeTextBeforeClick = controller.activeNativeText
        let nativeSelectionBeforeClick = controller.activeNativeSelectedRange
        let canonicalSelectionBeforeClick = controller.session.editorModel.selection
        var updates: [EditorUpdate] = []
        controller.onUpdate = { updates.append($0) }

        // When
        try send(.leftMouseDown, at: checkbox.center, fixture: fixture)
        try send(.leftMouseUp, at: checkbox.center, fixture: fixture)

        // Then
        #expect(controller.todoState(blockID: todo) == .on)
        #expect(controller.hasActiveNativeMarkedText)
        #expect(controller.activeNativeMarkedRange == markedRangeBeforeClick)
        #expect(controller.snapshot?.composition == compositionBeforeClick)
        #expect(controller.session.editorModel.selection == canonicalSelectionBeforeClick)
        #expect(controller.commandState.selectionMode == .text)
        #expect(updates.count == 1)
        #expect(updates.first?.committedDocumentRevision != nil)

        // When: native undo는 todo transaction 하나만 되돌린다.
        #expect(controller.handleNativeCommand(NSSelectorFromString("undo:")))

        // Then
        #expect(controller.todoState(blockID: todo) == .off)
        #expect(controller.hasActiveNativeMarkedText)
        #expect(controller.activeNativeMarkedRange == markedRangeBeforeClick)
        #expect(controller.snapshot?.composition == compositionBeforeClick)
        #expect(controller.session.editorModel.selection == canonicalSelectionBeforeClick)
        #expect(controller.snapshot?.history.canUndo == false)
        #expect(updates.count == 2)
        #expect(updates.last?.committedDocumentRevision != nil)

        // When: native redo도 같은 marked surface 위에서 todo만 다시 적용한다.
        #expect(controller.handleNativeCommand(NSSelectorFromString("redo:")))

        // Then
        #expect(controller.todoState(blockID: todo) == .on)
        #expect(controller.hasActiveNativeMarkedText)
        #expect(controller.activeNativeMarkedRange == markedRangeBeforeClick)
        #expect(
            controller.activeNativeMarkedReplacementRange == markedReplacementRangeBeforeClick
        )
        #expect(controller.activeNativeMarkedDocumentText == markedDocumentTextBeforeClick)
        #expect(controller.activeNativeText == nativeTextBeforeClick)
        #expect(controller.activeNativeSelectedRange == nativeSelectionBeforeClick)
        #expect(controller.snapshot?.composition == compositionBeforeClick)
        #expect(controller.session.editorModel.selection == canonicalSelectionBeforeClick)
        #expect(controller.snapshot?.history.canUndo == true)
        #expect(controller.snapshot?.history.canRedo == false)
        #expect(updates.count == 3)
        #expect(
            updates.compactMap { $0.committedDocumentRevision?.rawValue } == [1, 2, 3]
        )

        // When: 이어지는 marked replacement가 보존된 원본 baseline을 다시 사용한다.
        controller.setMarkedTextFromNativeSurface(
            "한글",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        // Then
        #expect(controller.hasActiveNativeMarkedText)
        #expect(controller.activeNativeText == "한글")
        #expect(controller.activeNativeMarkedReplacementRange == markedReplacementRangeBeforeClick)
        #expect(controller.activeNativeMarkedDocumentText == markedDocumentTextBeforeClick)
        #expect(
            controller.snapshot?.composition?.replacementRange
                == compositionBeforeClick.replacementRange)
        #expect(controller.session.editorModel.selection == canonicalSelectionBeforeClick)
        #expect(controller.documentSnapshot.blocks.first?.content.text == "Text")
        #expect(
            updates.compactMap { $0.committedDocumentRevision?.rawValue } == [1, 2, 3]
        )
    }

    @Test("selected todo checkbox drag-out release-outside는 block drag와 toggle을 모두 취소한다")
    func givenSelectedTodoCheckbox_whenDraggingOutAndReleasingOutside_thenGestureIsCancelled()
        throws
    {
        // Given
        let todo: BlockID = "todo"
        let sibling: BlockID = "sibling"
        let originalSelection = EditorSelection.blocks(BlockSelection(blockIDs: [todo]))
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: todo, kind: .todo(isChecked: false), content: .init(text: "A")),
                EditorBlockInput(id: sibling, content: .init(text: "B")),
            ],
            selection: originalSelection,
            focusOnAppear: false
        )
        let fixture = try mounted(controller)
        defer { fixture.close() }
        let checkbox = try #require(controller.todoCheckboxHitRect(blockID: todo))
        let outside = CGPoint(x: checkbox.maxX + 24, y: checkbox.midY)

        // When
        try send(.leftMouseDown, at: checkbox.center, fixture: fixture)
        try send(.leftMouseDragged, at: outside, fixture: fixture)
        try send(.leftMouseUp, at: outside, fixture: fixture)

        // Then
        #expect(controller.todoState(blockID: todo) == .off)
        #expect(controller.snapshot?.selection == originalSelection)
        #expect(controller.snapshot?.blockDragState == nil)
        #expect(controller.snapshot?.blockSelectionRectangleState == nil)
        #expect(controller.perform(.undo, makeFirstResponder: false) == nil)
    }

    @Test("checkbox에서 나갔다가 같은 hit zone 안에 release하면 정확히 한 번 toggle한다")
    func givenPressedCheckbox_whenDraggingOutThenReleasingInside_thenReleaseInsideWins() throws {
        // Given
        let todo: BlockID = "todo"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: todo, kind: .todo(isChecked: false))],
            selection: .blocks(BlockSelection(blockIDs: [todo])),
            focusOnAppear: false
        )
        let fixture = try mounted(controller)
        defer { fixture.close() }
        let checkbox = try #require(controller.todoCheckboxHitRect(blockID: todo))

        // When
        try send(.leftMouseDown, at: checkbox.center, fixture: fixture)
        try send(
            .leftMouseDragged,
            at: CGPoint(x: checkbox.maxX + 24, y: checkbox.midY),
            fixture: fixture
        )
        try send(.leftMouseDragged, at: checkbox.center, fixture: fixture)
        try send(.leftMouseUp, at: checkbox.center, fixture: fixture)

        // Then
        #expect(controller.todoState(blockID: todo) == .on)
        #expect(controller.snapshot?.blockDragState == nil)
    }

    @Test("non-todo 같은 gutter 위치는 checkbox가 아니라 기존 block selection gesture다")
    func givenNonTodoGutter_whenClickingMarkerPosition_thenExistingGutterSemanticsRemain() throws {
        // Given
        let paragraph: BlockID = "paragraph"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: paragraph, content: .init(text: "Body"))],
            selection: .inactive,
            focusOnAppear: false
        )
        let fixture = try mounted(controller)
        defer { fixture.close() }
        let block = try #require(controller.snapshot?.visibleBlocks.first)
        let markerPoint = CGPoint(
            x: controller.editorStyle.gutterWidth / 2,
            y: block.frame.y + 17
        )

        // When
        try send(.leftMouseDown, at: markerPoint, fixture: fixture)
        try send(.leftMouseUp, at: markerPoint, fixture: fixture)

        // Then
        guard case .blocks(let selection) = controller.snapshot?.selection else {
            Issue.record("non-todo gutter click이 기존 BlockSelection을 만들지 않음")
            return
        }
        #expect(selection.blockIDs == [paragraph])
        #expect(controller.todoState(blockID: paragraph) == .unavailable)
    }

    private func mounted(_ controller: AppKitEditorViewController) throws -> Fixture {
        _ = NSApplication.shared
        let window = AppKitTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 300)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        return Fixture(window: window, controller: controller)
    }

    private func send(
        _ type: NSEvent.EventType,
        at documentPoint: CGPoint,
        fixture: Fixture
    ) throws {
        let windowPoint = fixture.controller.canvasView.convert(documentPoint, to: nil)
        let event = try #require(
            NSEvent.mouseEvent(
                with: type,
                location: windowPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: fixture.window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            )
        )
        fixture.window.sendEvent(event)
    }

    @MainActor
    private struct Fixture {
        let window: AppKitTestWindow
        let controller: AppKitEditorViewController

        func close() {
            controller.setFocused(false)
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }
    }
}

extension CGRect {
    fileprivate var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
