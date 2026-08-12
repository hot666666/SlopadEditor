import AppKit
import SlopadEditorEngine
import Testing

@testable import SlopadEditorAppKitUI

@MainActor
@Suite("AppKit floating formatting toolbar")
struct AppKitFloatingFormattingToolbarTests {
    @Test("stable BlockSelection은 mixed inline state와 visible anchor toolbar를 표시한다")
    func givenStableMixedBlockSelection_whenRendering_thenToolbarShowsMixedState() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: a,
                    content: BlockContent(
                        text: "Alpha",
                        marks: [.init(kind: .strong, range: TextRange(0, 5))]
                    )
                ),
                EditorBlockInput(id: b, content: .init(text: "Bravo")),
            ],
            selection: .blocks(BlockSelection(blockIDs: [a, b])),
            focusOnAppear: false
        )
        let fixture = mounted(controller)
        defer { fixture.close() }

        // When
        controller.renderAndSyncSurface(makeFirstResponder: false)

        // Then
        let strong = try #require(controller.floatingFormattingToolbarItemState(.strong))
        let toolbarFrame = try #require(controller.floatingFormattingToolbarFrame)
        #expect(controller.isFloatingFormattingToolbarPresented)
        #expect(strong.isEnabled)
        #expect(strong.value == .mixed)
        #expect(!strong.commitsComposition)
        #expect(controller.view.bounds.contains(toolbarFrame))
    }

    @Test("toolbar action은 BlockSelection mode를 유지하고 한 번의 update와 undo를 만든다")
    func givenBlockSelection_whenClickingBold_thenSelectionAndSingleUndoArePreserved() throws {
        // Given
        let a: BlockID = "a"
        let child: BlockID = "child"
        let b: BlockID = "b"
        let selection = BlockSelection(blockIDs: [a, child, b], anchor: a, focus: b)
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(id: a, content: .init(text: "A")),
                EditorBlockInput(id: child, parentID: a, content: .init(text: "C")),
                EditorBlockInput(id: b, content: .init(text: "B")),
            ],
            selection: .blocks(selection),
            focusOnAppear: false
        )
        let fixture = mounted(controller)
        defer { fixture.close() }
        var updates: [EditorUpdate] = []
        controller.onUpdate = { updates.append($0) }
        controller.renderAndSyncSurface(makeFirstResponder: false)

        // When
        controller.performFloatingFormattingToolbarItem(.strong)

        // Then
        guard case .blocks(let afterSelection) = controller.snapshot?.selection else {
            Issue.record("toolbar action 뒤 BlockSelection이 유지되지 않음")
            return
        }
        #expect(afterSelection == selection)
        #expect(updates.count == 1)
        #expect(controller.floatingFormattingToolbarItemState(.strong)?.value == .on)
        #expect(controller.floatingFormattingToolbarItemState(.clear)?.isEnabled == true)
        #expect(
            controller.documentSnapshot.blocks.allSatisfy { block in
                block.content.text.isEmpty
                    || block.content.marks == [
                        .init(kind: .strong, range: TextRange(0, block.content.length))
                    ]
            })
        _ = try #require(controller.perform(.undo, makeFirstResponder: false))
        #expect(controller.documentSnapshot.blocks.allSatisfy { $0.content.marks.isEmpty })
    }

    @Test("built-in toolbar와 공개 host action은 같은 Session/model transaction과 undo 결과를 만든다")
    func givenEquivalentSelections_whenUsingToolbarAndHostAction_thenResultsAndUndoMatch() throws {
        // Given
        let a: BlockID = "a"
        let child: BlockID = "child"
        let b: BlockID = "b"
        let blocks = [
            EditorBlockInput(id: a, content: .init(text: "Alpha")),
            EditorBlockInput(id: child, parentID: a, content: .init(text: "Child")),
            EditorBlockInput(id: b, content: .init(text: "Bravo")),
        ]
        let selection = EditorSelection.blocks(
            BlockSelection(blockIDs: [a, child, b], anchor: a, focus: b)
        )
        let toolbarController = AppKitEditorViewController(
            blocks: blocks,
            selection: selection,
            focusOnAppear: false
        )
        let hostController = AppKitEditorViewController(
            blocks: blocks,
            selection: selection,
            focusOnAppear: false
        )
        let toolbarFixture = mounted(toolbarController)
        let hostFixture = mounted(hostController)
        defer {
            hostFixture.close()
            toolbarFixture.close()
        }
        var toolbarUpdates: [EditorUpdate] = []
        var hostUpdates: [EditorUpdate] = []
        toolbarController.onUpdate = { toolbarUpdates.append($0) }
        hostController.onUpdate = { hostUpdates.append($0) }
        toolbarController.renderAndSyncSurface(makeFirstResponder: false)
        hostController.renderAndSyncSurface(makeFirstResponder: false)

        // When
        toolbarController.performFloatingFormattingToolbarItem(.strong)
        let hostUpdate = try #require(
            hostController.perform(
                AppKitEditorAction.toggleInlineStyle(.strong),
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        )

        // Then
        #expect(hostUpdate.committedDocumentRevision?.rawValue == 1)
        #expect(toolbarUpdates.count == 1)
        #expect(hostUpdates.count == 1)
        #expect(toolbarController.documentSnapshot.blocks == hostController.documentSnapshot.blocks)
        #expect(toolbarController.snapshot?.selection == hostController.snapshot?.selection)
        #expect(toolbarController.snapshot?.history.canUndo == true)
        #expect(hostController.snapshot?.history.canUndo == true)

        // When: 같은 undo/redo가 strong transaction 하나만 왕복한다.
        let toolbarStrongUndo = try #require(
            toolbarController.perform(.undo, makeFirstResponder: false)
        )
        let hostStrongUndo = try #require(
            hostController.perform(.undo, makeFirstResponder: false)
        )
        let toolbarStrongRedo = try #require(
            toolbarController.perform(.redo, makeFirstResponder: false)
        )
        let hostStrongRedo = try #require(
            hostController.perform(.redo, makeFirstResponder: false)
        )

        // Then
        #expect(toolbarStrongUndo.committedDocumentRevision?.rawValue == 2)
        #expect(hostStrongUndo.committedDocumentRevision?.rawValue == 2)
        #expect(toolbarStrongRedo.committedDocumentRevision?.rawValue == 3)
        #expect(hostStrongRedo.committedDocumentRevision?.rawValue == 3)
        #expect(toolbarController.documentSnapshot.blocks == hostController.documentSnapshot.blocks)
        #expect(toolbarController.snapshot?.selection == selection)
        #expect(hostController.snapshot?.selection == selection)

        // When: clear도 built-in과 공개 action에서 같은 한 transaction으로 적용된다.
        toolbarController.performFloatingFormattingToolbarItem(.clear)
        let hostClear = try #require(
            hostController.perform(
                AppKitEditorAction.clearInlineStyles,
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        )

        // Then
        #expect(hostClear.committedDocumentRevision?.rawValue == 4)
        #expect(toolbarUpdates.count == 4)
        #expect(hostUpdates.count == 4)
        #expect(toolbarController.documentSnapshot.blocks == hostController.documentSnapshot.blocks)
        #expect(toolbarController.documentSnapshot.blocks.allSatisfy { $0.content.marks.isEmpty })
        #expect(toolbarController.snapshot?.selection == selection)
        #expect(hostController.snapshot?.selection == selection)

        // When: clear undo/redo도 strong 결과만 복원했다가 다시 제거한다.
        let toolbarClearUndo = try #require(
            toolbarController.perform(.undo, makeFirstResponder: false)
        )
        let hostClearUndo = try #require(
            hostController.perform(.undo, makeFirstResponder: false)
        )
        let toolbarBlocksAfterClearUndo = toolbarController.documentSnapshot.blocks
        let hostBlocksAfterClearUndo = hostController.documentSnapshot.blocks
        let toolbarClearRedo = try #require(
            toolbarController.perform(.redo, makeFirstResponder: false)
        )
        let hostClearRedo = try #require(
            hostController.perform(.redo, makeFirstResponder: false)
        )

        // Then
        #expect(toolbarClearUndo.committedDocumentRevision?.rawValue == 5)
        #expect(hostClearUndo.committedDocumentRevision?.rawValue == 5)
        #expect(toolbarBlocksAfterClearUndo == hostBlocksAfterClearUndo)
        #expect(
            toolbarBlocksAfterClearUndo.allSatisfy {
                $0.content.text.isEmpty || !$0.content.marks.isEmpty
            }
        )
        #expect(toolbarClearRedo.committedDocumentRevision?.rawValue == 6)
        #expect(hostClearRedo.committedDocumentRevision?.rawValue == 6)
        #expect(toolbarController.documentSnapshot.blocks == hostController.documentSnapshot.blocks)
        #expect(toolbarController.documentSnapshot.blocks.allSatisfy { $0.content.marks.isEmpty })
        #expect(toolbarController.snapshot?.selection == selection)
        #expect(hostController.snapshot?.selection == selection)
        #expect(toolbarUpdates.count == 6)
        #expect(hostUpdates.count == 6)
    }

    @Test("empty BlockSelection은 toolbar를 표시하되 inline command를 unavailable로 disable한다")
    func givenEmptyBlockSelection_whenRendering_thenUnavailableButtonsAreDisabled() throws {
        // Given
        let blockID: BlockID = "empty"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: blockID)],
            selection: .blocks(BlockSelection(blockIDs: [blockID])),
            focusOnAppear: false
        )
        let fixture = mounted(controller)
        defer { fixture.close() }

        // When
        controller.renderAndSyncSurface(makeFirstResponder: false)

        // Then
        let strong = try #require(controller.floatingFormattingToolbarItemState(.strong))
        let clear = try #require(controller.floatingFormattingToolbarItemState(.clear))
        #expect(controller.isFloatingFormattingToolbarPresented)
        #expect(!strong.isEnabled)
        #expect(strong.value == .off)
        #expect(!clear.isEnabled)
    }

    @Test("composition 중 toolbar query와 표시만으로 commit하지 않고 action 시 명시적으로 commit한다")
    func givenComposition_whenOpeningThenClickingToolbar_thenOnlyClickCommits() throws {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: blockID, content: .init(text: "abcd"))],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: blockID, offset: 1),
                    focus: TextPosition(blockID: blockID, offset: 3)
                )
            ),
            focusOnAppear: false
        )
        let fixture = mounted(controller)
        defer { fixture.close() }
        controller.renderAndSyncSurface(makeFirstResponder: true)
        controller.canvasView.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 1, length: 2)
        )
        let stateBeforeClick = try #require(
            controller.floatingFormattingToolbarItemState(.strong)
        )
        let toolbarWasPresentedBeforeClick = controller.isFloatingFormattingToolbarPresented

        // When
        controller.renderAndSyncSurface(makeFirstResponder: true)
        let compositionAfterOpening = controller.snapshot?.composition
        controller.performFloatingFormattingToolbarItem(.strong)

        // Then
        #expect(toolbarWasPresentedBeforeClick)
        #expect(stateBeforeClick.isEnabled)
        #expect(stateBeforeClick.commitsComposition)
        #expect(compositionAfterOpening != nil)
        #expect(controller.snapshot?.composition == nil)
        #expect(controller.documentSnapshot.blocks[0].content.text == "a한d")
        #expect(controller.commandState.toggleState(for: .strong) == .on)
        #expect(fixture.window.firstResponder === controller.canvasView)
    }

    @Test("selection geometry가 없거나 caret이면 toolbar를 숨긴다")
    func givenNoUsableSelectionGeometry_whenRendering_thenToolbarIsHidden() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(id: a, content: .init(text: "A")),
                EditorBlockInput(id: b, content: .init(text: "B")),
            ],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: a, offset: 1),
                    focus: TextPosition(blockID: b, offset: 0)
                )
            ),
            focusOnAppear: false
        )
        let fixture = mounted(controller)
        defer { fixture.close() }

        // When
        controller.renderAndSyncSurface(makeFirstResponder: false)

        // Then
        #expect(!controller.isFloatingFormattingToolbarPresented)
    }

    @Test("placement는 좌우 clamp하고 위 공간이 없으면 아래로 뒤집힌다")
    func givenEdgeAnchors_whenPlacingToolbar_thenFrameClampsAndFlips() {
        // Given
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let size = NSSize(width: 120, height: 40)

        // When
        let left = AppKitFloatingFormattingToolbar.placementFrame(
            anchor: CGRect(x: 0, y: 80, width: 10, height: 10),
            toolbarSize: size,
            containerBounds: bounds
        )
        let right = AppKitFloatingFormattingToolbar.placementFrame(
            anchor: CGRect(x: 290, y: 80, width: 10, height: 10),
            toolbarSize: size,
            containerBounds: bounds
        )
        let top = AppKitFloatingFormattingToolbar.placementFrame(
            anchor: CGRect(x: 140, y: 180, width: 10, height: 10),
            toolbarSize: size,
            containerBounds: bounds
        )
        let bottom = AppKitFloatingFormattingToolbar.placementFrame(
            anchor: CGRect(x: 140, y: 0, width: 10, height: 10),
            toolbarSize: size,
            containerBounds: bounds
        )

        // Then
        #expect(left.frame.minX == 8)
        #expect(right.frame.maxX == 292)
        #expect(top.placement == .below)
        #expect(top.frame.maxY <= 180)
        #expect(bottom.placement == .above)
        #expect(bottom.frame.minY >= 10)
        #expect(
            [left.frame, right.frame, top.frame, bottom.frame].allSatisfy {
                bounds.contains($0)
            })
    }

    private func mounted(_ controller: AppKitEditorViewController) -> Fixture {
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
        return Fixture(window: window, controller: controller)
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
