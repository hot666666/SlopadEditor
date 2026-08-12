import AppKit
import SlopadEditorEngine
import Testing

@testable import SlopadEditorAppKitUI

@MainActor
@Suite("AppKit native mouse text selection")
struct AppKitEditorViewControllerMouseTextSelectionTests {
    @Test("mouse down drag up 경로가 responder와 text selection을 동기화한다")
    func nativeMouseDragProducesTextSelection() throws {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(
                    id: blockID,
                    content: BlockContent(text: String(repeating: "selection ", count: 30))
                )
            ],
            selection: .caret(blockID: blockID, offset: 0),
            focusOnAppear: false
        )
        let window = AppKitTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.contentViewController = controller
        controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 240)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let frame = try #require(
            controller.session.blockRevealFrame(
                for: blockID,
                viewport: controller.currentViewport()
            )
        )
        let textOriginX =
            controller.editorStyle.gutterWidth
            + controller.editorStyle.contentHorizontalPadding
        let start = CGPoint(x: textOriginX + 8, y: frame.y + frame.height * 0.5)
        let end = CGPoint(x: textOriginX + 220, y: start.y)

        // When
        controller.handleMouseDown(documentPoint: start, clickCount: 1)
        for step in 1...4 {
            let progress = Double(step) / 4
            controller.handleMouseDragged(
                documentPoint: CGPoint(
                    x: start.x + (end.x - start.x) * CGFloat(progress),
                    y: start.y
                )
            )
        }
        controller.handleMouseUp(documentPoint: end)

        // Then
        #expect(window.firstResponder === controller.canvasView)
        guard case .text(let selection) = controller.snapshot?.selection else {
            Issue.record("native mouse drag가 text selection을 남기지 않음")
            return
        }
        #expect(selection.isSingleBlock)
        #expect(selection.anchor.offset != selection.focus.offset)
    }

    @Test("NSWindow drag event는 text lane 시작 모드를 고정하고 다음 블록 글자까지 TN을 만든다")
    func nativeWindowDragProducesCrossBlockTextSelection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(id: a, content: BlockContent(text: "Alpha")),
                EditorBlockInput(id: b, content: BlockContent(text: "Bravo")),
                EditorBlockInput(id: c, content: BlockContent(text: "Charlie")),
            ],
            selection: .inactive,
            focusOnAppear: false
        )
        let window = AppKitTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        defer {
            controller.setFocused(false)
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }
        controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 300)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let snapshot = try #require(controller.snapshot)
        let first = try #require(snapshot.visibleBlocks.first { $0.id == a })
        let last = try #require(snapshot.visibleBlocks.first { $0.id == c })
        let startDocument = CGPoint(
            x: first.textRender.frame.x + 8,
            y: first.textRender.frame.midY
        )
        let endDocument = CGPoint(
            x: last.textRender.frame.x + 32,
            y: last.textRender.frame.midY
        )
        let start = controller.canvasView.convert(startDocument, to: nil)
        let end = controller.canvasView.convert(endDocument, to: nil)

        // When
        let events: [(NSEvent.EventType, CGPoint)] = [
            (.leftMouseDown, start),
            (.leftMouseDragged, end),
            (.leftMouseUp, end),
        ]
        for (type, point) in events {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type,
                    location: point,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: type == .leftMouseUp ? 0 : 1
                )
            )
            window.sendEvent(event)
        }

        // Then
        guard case .text(let selection) = controller.snapshot?.selection else {
            Issue.record("cross-block window drag가 TN을 만들지 않음")
            return
        }
        #expect(selection.anchor.blockID == a)
        #expect(selection.focus.blockID == c)
    }

    @Test("아래 block에서 위 block으로 drag하면 역방향 TN을 유지한다")
    func reverseDragProducesCrossBlockTextSelection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(id: a, content: BlockContent(text: "Alpha")),
                EditorBlockInput(id: b, content: BlockContent(text: "Bravo")),
                EditorBlockInput(id: c, content: BlockContent(text: "Charlie")),
            ],
            selection: .inactive,
            focusOnAppear: false
        )
        controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 300)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let snapshot = try #require(controller.snapshot)
        let first = try #require(snapshot.visibleBlocks.first { $0.id == a })
        let last = try #require(snapshot.visibleBlocks.first { $0.id == c })
        let start = CGPoint(
            x: last.textRender.frame.x + 32,
            y: last.textRender.frame.midY
        )
        let end = CGPoint(
            x: first.textRender.frame.x + 8,
            y: first.textRender.frame.midY
        )

        // When
        controller.handleMouseDown(documentPoint: start, clickCount: 1)
        controller.handleMouseDragged(documentPoint: end)
        controller.handleMouseUp(documentPoint: end)

        // Then
        guard case .text(let selection) = controller.snapshot?.selection else {
            Issue.record("역방향 drag가 cross-block text selection을 남기지 않음")
            return
        }
        #expect(selection.anchor.blockID == c)
        #expect(selection.focus.blockID == a)
        #expect(
            controller.snapshot?.selectionPresentation.visibleTextSelections.map(\.blockID)
                == [a, b, c]
        )
        #expect(controller.snapshot?.activeTextInput?.renderDescriptor.measureRequest.blockID == a)
    }

    @Test("NSWindow gutter drag는 글자 위를 지나도 block selection 모드를 유지한다")
    func nativeWindowGutterDragProducesBlockSelection() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(id: a, content: BlockContent(text: "Alpha")),
                EditorBlockInput(id: b, content: BlockContent(text: "Bravo")),
                EditorBlockInput(id: c, content: BlockContent(text: "Charlie")),
            ],
            selection: .inactive,
            focusOnAppear: false
        )
        let window = AppKitTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        defer {
            controller.setFocused(false)
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }
        controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 300)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let snapshot = try #require(controller.snapshot)
        let first = try #require(snapshot.visibleBlocks.first { $0.id == a })
        let last = try #require(snapshot.visibleBlocks.first { $0.id == c })
        let start = controller.canvasView.convert(
            CGPoint(x: controller.editorStyle.gutterWidth * 0.5, y: first.frame.midY),
            to: nil
        )
        let end = controller.canvasView.convert(
            CGPoint(x: last.textRender.frame.midX, y: last.frame.midY),
            to: nil
        )

        // When
        for (type, point) in [
            (NSEvent.EventType.leftMouseDown, start),
            (.leftMouseDragged, end),
            (.leftMouseUp, end),
        ] {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type,
                    location: point,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: type == .leftMouseUp ? 0 : 1
                ))
            window.sendEvent(event)
        }

        // Then
        guard case .blocks(let selection) = controller.snapshot?.selection else {
            Issue.record("gutter drag가 block selection을 만들지 않음")
            return
        }
        #expect(selection.blockIDs == [a, b, c])
    }

    @Test("text selection 자동 스크롤은 모드를 유지하며 화면 밖 블록으로 TN을 확장한다")
    func textSelectionAutoscrollExtendsCrossBlockRange() throws {
        // Given
        let blocks = (0..<100).map { index in
            EditorBlockInput(
                id: BlockID("block-\(index)"),
                content: BlockContent(text: "Block \(index) selection text")
            )
        }
        let firstID = try #require(blocks.first?.id)
        let controller = AppKitEditorViewController(
            blocks: blocks,
            selection: .inactive,
            focusOnAppear: false
        )
        controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 180)
        controller.view.layoutSubtreeIfNeeded()
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let first = try #require(
            controller.snapshot?.visibleBlocks.first { $0.id == firstID }
        )
        let x = first.textRender.frame.x + 8
        let start = CGPoint(x: x, y: first.textRender.frame.midY)
        let initialY = controller.scrollView.contentView.bounds.origin.y
        let edgePoint = CGPoint(
            x: x,
            y: controller.scrollView.contentView.bounds.maxY - 1
        )

        // When
        controller.handleMouseDown(documentPoint: start, clickCount: 1)
        controller.handleMouseDragged(documentPoint: edgePoint)
        for _ in 0..<12 {
            controller.dragAutoscrollController.tick()
        }
        let finalPoint = CGPoint(
            x: x,
            y: controller.scrollView.contentView.bounds.maxY - 1
        )
        controller.handleMouseUp(documentPoint: finalPoint)

        // Then
        #expect(controller.scrollView.contentView.bounds.origin.y > initialY)
        guard case .text(let selection) = controller.snapshot?.selection else {
            Issue.record("자동 스크롤 뒤 text selection이 유지되지 않음")
            return
        }
        #expect(selection.anchor.blockID == firstID)
        #expect(selection.focus.blockID != firstID)
    }
}
