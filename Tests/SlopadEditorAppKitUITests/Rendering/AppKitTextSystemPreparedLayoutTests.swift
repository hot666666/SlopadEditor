#if SLOPAD_BENCHMARK_INSTRUMENTATION
    import AppKit
    import Testing

    import SlopadEditorEngine
    @testable import SlopadEditorAppKitUI

    @MainActor
    @Suite("AppKit text system prepared layout 재사용")
    struct AppKitTextSystemPreparedLayoutTests {
        @Test("production 조립은 renderer와 layouter에 하나의 prepared state를 제공한다")
        func productionCompositionSharesPreparedState() throws {
            // Given
            let system = AppKitTextSystem(style: AppKitEditorStyle())
            let request = BlockMeasureRequest(
                blockID: "block",
                text: "Body text",
                kind: .paragraph,
                availableWidth: 320,
                depth: 0
            )
            let context = try #require(makeBitmapContext())

            // When
            system.textRenderer.draw(
                request,
                in: CGRect(x: 0, y: 0, width: 320, height: 120),
                context: context
            )
            _ = system.textLayouter.caretRect(
                for: TextPosition(blockID: request.blockID, offset: 2),
                in: request
            )

            // Then: identity는 production 조립을, counter는 same-key 재사용을 고정한다.
            #expect(
                system.textLayouter.layoutContextIdentifierForInstrumentation
                    == system.textRenderer.layoutContextIdentifierForInstrumentation
            )
            let snapshot = system.textLayouter.contextPreparedLayoutInstrumentation
            #expect(snapshot.lookups == 2)
            #expect(snapshot.hits == 1)
            #expect(snapshot.prepares == 1)
            #expect(snapshot.attributedStringBuilds == 1)
        }

        @Test("production surface sync는 active text block을 pin한다")
        func productionSurfaceSyncPinsActiveTextBlock() {
            // Given
            let activeBlockID: BlockID = "active"
            let controller = AppKitEditorViewController(
                blocks: [
                    EditorBlockInput(
                        id: activeBlockID,
                        content: BlockContent(text: "조합")
                    )
                ],
                selection: .caret(blockID: activeBlockID, offset: 1)
            )
            controller.loadView()

            // When
            controller.renderAndSyncSurface(makeFirstResponder: false)
            let snapshot = controller.preparedLayoutInstrumentation

            // Then
            #expect(snapshot.pinnedEntryCount == 1)
            #expect(snapshot.residentEntryCount >= 1)
        }

        @Test("active text block이 viewport 밖이어도 pin을 유지한다")
        func offscreenActiveTextBlockRemainsPinned() {
            // Given
            let activeBlockID: BlockID = "block-0"
            let blocks = (0..<100).map { index in
                EditorBlockInput(
                    id: BlockID("block-\(index)"),
                    content: BlockContent(text: "Block \(index) long enough to measure")
                )
            }
            let controller = AppKitEditorViewController(
                blocks: blocks,
                selection: .caret(blockID: activeBlockID, offset: 1)
            )
            controller.loadView()
            controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 240)
            controller.scrollView.frame = controller.view.bounds
            controller.renderAndSyncSurface(makeFirstResponder: false)

            // When
            controller.scrollDocument(to: 100_000)
            let snapshot = controller.preparedLayoutInstrumentation

            // Then
            #expect(controller.snapshot?.activeTextInput == nil)
            #expect(snapshot.pinnedEntryCount == 1)
            #expect(snapshot.residentEntryCount <= 96)
        }

        @Test("TN의 offscreen focus는 reveal 뒤 active native input과 prepared pin을 소유한다")
        func crossBlockFocusRevealsAndPinsNativeInput() throws {
            // Given
            let blocks = (0..<100).map { index in
                EditorBlockInput(
                    id: BlockID("tn-focus-\(index)"),
                    content: BlockContent(text: "Block \(index) long enough to measure")
                )
            }
            let focusID = blocks[99].id
            let selection = TextSelection(
                anchor: TextPosition(blockID: blocks[0].id, offset: 1),
                focus: TextPosition(blockID: focusID, offset: 3)
            )
            let controller = AppKitEditorViewController(
                blocks: blocks,
                selection: .text(selection)
            )
            let window = AppKitTestWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 240),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            defer {
                controller.setFocused(false)
                window.contentViewController = nil
                window.close()
            }
            controller.view.frame = window.contentView?.bounds ?? .zero
            controller.view.layoutSubtreeIfNeeded()

            // When
            controller.renderAndSyncSurface(
                makeFirstResponder: true,
                scrollSelectionIntoView: true
            )
            let instrumentation = controller.preparedLayoutInstrumentation

            // Then
            #expect(controller.snapshot?.selection == .text(selection))
            #expect(controller.currentViewport().scrollY > 0)
            #expect(
                controller.snapshot?.activeTextInput?.renderDescriptor.measureRequest.blockID
                    == focusID
            )
            #expect(controller.activeNativeText == blocks[99].content.text)
            #expect(window.firstResponder === controller.canvasView)
            #expect(instrumentation.pinnedEntryCount == 1)
            #expect(instrumentation.pinnedBlockIDAtLastPrepare == focusID)
        }

        @Test("visible block이 limit보다 많아도 initial render와 draw에서 active는 한 번만 준비한다")
        func initialRenderAndDrawRetainActiveEntry() throws {
            // Given
            let controller = makeLargeController(prefix: "initial")

            // When
            controller.renderAndSyncSurface(makeFirstResponder: false)
            let afterRender = controller.preparedLayoutInstrumentation
            let visibleCount = try #require(controller.snapshot?.visibleBlocks.count)
            try drawOnce(controller)
            let afterDraw = controller.preparedLayoutInstrumentation

            // Then
            #expect(visibleCount > 96)
            #expect(afterRender.pinnedEntryCount == 1)
            #expect(afterDraw.lookups - afterRender.lookups == visibleCount)
            #expect(afterDraw.hits - afterRender.hits == 1)
            #expect(afterDraw.prepares - afterRender.prepares == visibleCount - 1)
        }

        @Test("reset의 첫 render와 draw 전에도 새 active block을 pin한다")
        func resetPinsBeforeFirstRenderAndDraw() throws {
            // Given
            let controller = makeLargeController(prefix: "old")
            controller.renderAndSyncSurface(makeFirstResponder: false)
            let replacement = makeBlocks(prefix: "reset")

            // When
            controller.resetDocumentWithoutRendering(
                blocks: replacement,
                selection: .caret(blockID: replacement[0].id, offset: 1)
            )
            controller.renderAndSyncSurface(makeFirstResponder: false)
            let afterRender = controller.preparedLayoutInstrumentation
            let visibleCount = try #require(controller.snapshot?.visibleBlocks.count)
            try drawOnce(controller)
            let afterDraw = controller.preparedLayoutInstrumentation

            // Then
            #expect(visibleCount > 96)
            #expect(afterRender.pinnedEntryCount == 1)
            #expect(afterDraw.hits - afterRender.hits == 1)
            #expect(afterDraw.prepares - afterRender.prepares == visibleCount - 1)
        }

        @Test("style 교체 backend의 첫 render와 draw 전에도 active block을 pin한다")
        func styleChangePinsBeforeFirstRenderAndDraw() throws {
            // Given
            let controller = makeLargeController(prefix: "style")
            controller.renderAndSyncSurface(makeFirstResponder: false)

            // When
            controller.updateEditorStyle(AppKitEditorStyle(fontSize: 18))
            let afterRender = controller.preparedLayoutInstrumentation
            let visibleCount = try #require(controller.snapshot?.visibleBlocks.count)
            try drawOnce(controller)
            let afterDraw = controller.preparedLayoutInstrumentation

            // Then
            #expect(visibleCount > 96)
            #expect(afterRender.pinnedEntryCount == 1)
            #expect(afterDraw.hits - afterRender.hits == 1)
            #expect(afterDraw.prepares - afterRender.prepares == visibleCount - 1)
        }

        @Test("대용량 patch의 selection 변경은 첫 render 전에 새 active block을 pin한다")
        func documentPatchSelectionChangePinsBeforeFirstRenderAndDraw() throws {
            // Given
            let controller = makeLargeController(prefix: "patch")
            controller.renderAndSyncSurface(makeFirstResponder: false)
            let context = try controller.documentContextSnapshot()
            let newActiveBlockID = context.document.blocks[1].id
            let patch = EditorDocumentPatch(
                source: context.source,
                replacementBlocks: context.document.blocks,
                selectionAfter: .caret(blockID: newActiveBlockID, offset: 1)
            )
            let beforePatch = controller.preparedLayoutInstrumentation

            // When
            let appliedUpdate = try controller.applyDocumentPatch(patch)
            _ = try #require(appliedUpdate)
            let afterRender = controller.preparedLayoutInstrumentation
            let visibleCount = try #require(controller.snapshot?.visibleBlocks.count)
            try drawOnce(controller)
            let afterDraw = controller.preparedLayoutInstrumentation

            // Then
            #expect(visibleCount > 96)
            #expect(controller.snapshot?.selection == .caret(blockID: newActiveBlockID, offset: 1))
            #expect(afterRender.pinnedEntryCount == 1)
            #expect(afterRender.prepares - beforePatch.prepares == 1)
            #expect(afterRender.pinnedBlockIDAtLastPrepare == newActiveBlockID)
            #expect(afterDraw.hits - afterRender.hits == 2)
            #expect(afterDraw.prepares - afterRender.prepares == visibleCount - 2)
        }

        @Test("IME handoff는 다음 render 전에 새 active block으로 pin을 옮긴다")
        func imeHandoffPinsBeforeNextRender() throws {
            // Given
            let firstID: BlockID = "first"
            let secondID: BlockID = "second"
            let controller = AppKitEditorViewController(
                blocks: [
                    EditorBlockInput(id: firstID, content: BlockContent(text: "first")),
                    EditorBlockInput(id: secondID, content: BlockContent(text: "second")),
                ],
                selection: .caret(blockID: firstID, offset: 1)
            )
            controller.loadView()
            controller.renderAndSyncSurface(makeFirstResponder: false)
            let secondDescriptor = try #require(
                controller.snapshot?.visibleBlocks.first { $0.id == secondID }?.textRender
            )

            // When
            _ = controller.handleInputWithoutRendering(
                .activeTextSelectionChanged(
                    blockID: secondID,
                    selectedRange: TextRange.point(1)
                )
            )
            _ = controller.handleInputWithoutRendering(
                .beginComposition(
                    blockID: secondID,
                    replacementRange: TextRange(0, 1),
                    text: "조"
                )
            )
            controller.handlePreparedLayoutMemoryPressure(.warning)
            let beforeLookup = controller.preparedLayoutInstrumentation
            _ = controller.session.textLineFragmentRects(in: secondDescriptor)
            let afterLookup = controller.preparedLayoutInstrumentation

            // Then
            #expect(beforeLookup.pinnedEntryCount == 1)
            #expect(afterLookup.hits - beforeLookup.hits == 1)
            #expect(afterLookup.prepares == beforeLookup.prepares)
        }

        private func makeLargeController(prefix: String) -> AppKitEditorViewController {
            let blocks = makeBlocks(prefix: prefix)
            let controller = AppKitEditorViewController(
                blocks: blocks,
                selection: .caret(blockID: blocks[0].id, offset: 1)
            )
            controller.loadView()
            controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 12_000)
            controller.scrollView.frame = controller.view.bounds
            controller.scrollView.contentView.frame = controller.scrollView.bounds
            return controller
        }

        private func makeBlocks(prefix: String) -> [EditorBlockInput] {
            (0..<104).map { index in
                EditorBlockInput(
                    id: BlockID("\(prefix)-\(index)"),
                    content: BlockContent(text: "Block \(index) text")
                )
            }
        }

        private func drawOnce(_ controller: AppKitEditorViewController) throws {
            let bounds = controller.canvasView.bounds
            let context = try #require(
                CGContext(
                    data: nil,
                    width: max(1, Int(bounds.width.rounded(.up))),
                    height: max(1, Int(bounds.height.rounded(.up))),
                    bitsPerComponent: 8,
                    bytesPerRow: max(1, Int(bounds.width.rounded(.up))) * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            defer { NSGraphicsContext.restoreGraphicsState() }
            controller.drawCanvas(bounds)
        }

        private func makeBitmapContext() -> CGContext? {
            let width = 640
            let height = 240
            return CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
    }
#endif
