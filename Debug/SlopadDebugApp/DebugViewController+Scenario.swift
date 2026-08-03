import AppKit
import Foundation
import SlopadAppKitTextKit
import SlopadEngine

@MainActor
extension DebugViewController {
    // MARK: - Debug Init

    convenience init(scenario: String) {
        self.init(
            blocks: scenario == "basic-use"
                ? BasicUseFixture.makeBlocks()
                : scenario.hasPrefix("scroll-")
                    ? DebugScrollFixture.makeBlocks()
                    : DebugSeedFixture.makeBlocks(),
            selection: scenario == "basic-use"
                ? .caret(blockID: BasicUseFixture.title, offset: 0)
                : scenario.hasPrefix("scroll-")
                    ? .caret(blockID: DebugScrollFixture.blocks[0], offset: 0)
                    : .caret(blockID: DebugSeedFixture.intro, offset: 0),
            focusOnAppear: scenario == "basic-use" || scenario == "initial"
        )
    }

    // MARK: - Scenario Harness

    func performScenario(_ scenario: String) {
        switch scenario {
        case "basic-use":
            focus(blockID: BasicUseFixture.title, offset: 0)

        case "initial":
            click(blockID: DebugSeedFixture.intro, x: CGFloat(editorStyle.gutterWidth + 96))

        case "gutter-selection":
            click(blockID: DebugSeedFixture.todo, x: CGFloat(editorStyle.gutterWidth) * 0.5)

        case "gutter-drag-selection":
            dragBlockSelection(
                from: DebugSeedFixture.intro,
                to: DebugSeedFixture.code,
                x: CGFloat(editorStyle.gutterWidth) * 0.5
            )

        case "text-drag-selection":
            dragTextSelection(
                in: DebugSeedFixture.intro,
                fromTextX: 4,
                toTextX: 260
            )

        case "text-drag-clamp-to-block":
            dragTextSelectionAcrossBlocks(
                from: DebugSeedFixture.intro,
                to: DebugSeedFixture.todo
            )

        case "double-click-word-selection":
            doubleClickText(in: DebugSeedFixture.intro, textX: 96)

        case "double-click-block-text-selection":
            doubleClickText(in: DebugSeedFixture.intro, textX: 96)
            clickText(in: DebugSeedFixture.intro, textX: 96)
            doubleClickText(in: DebugSeedFixture.intro, textX: 96)

        case "drag-reorder":
            dragBlockSelection(
                from: DebugSeedFixture.intro,
                to: DebugSeedFixture.todo,
                x: CGFloat(editorStyle.gutterWidth) * 0.5
            )
            dragSelectedBlocks(
                from: DebugSeedFixture.intro,
                toAfter: DebugSeedFixture.code,
                x: CGFloat(editorStyle.gutterWidth) * 0.5
            )

        case "click-tail":
            click(blockID: DebugSeedFixture.tail, x: CGFloat(editorStyle.gutterWidth + 96))

        case "click-todo":
            click(blockID: DebugSeedFixture.intro, x: CGFloat(editorStyle.gutterWidth + 96))
            click(blockID: DebugSeedFixture.todo, x: CGFloat(editorStyle.gutterWidth + 96))

        case "ime-composition":
            click(blockID: DebugSeedFixture.intro, x: CGFloat(editorStyle.gutterWidth + 96))
            simulateComposition(text: "조합중")

        case "ime-marked-callback":
            focus(blockID: DebugSeedFixture.intro, offset: 0)
            renderAndSyncSurface(makeFirstResponder: true)
            simulateMarkedTextCallback(
                text: "조합", replacementRange: NSRange(location: 0, length: 5))

        case "ime-unmark-callback":
            focus(blockID: DebugSeedFixture.intro, offset: 0)
            renderAndSyncSurface(makeFirstResponder: true)
            simulateMarkedTextCallback(
                text: "조합", replacementRange: NSRange(location: 0, length: 5))
            unmarkTextFromNativeSurface()

        case "move-down":
            let offset =
                snapshotText(for: DebugSeedFixture.intro)?.count ?? DebugSeedFixture.introText.count
            focus(blockID: DebugSeedFixture.intro, offset: offset)
            renderAndSyncSurface(makeFirstResponder: true)
            _ = handleNativeCommand(#selector(NSResponder.moveDown(_:)))

        case "move-up":
            focus(blockID: DebugSeedFixture.tail, offset: 0)
            renderAndSyncSurface(makeFirstResponder: true)
            _ = handleNativeCommand(#selector(NSResponder.moveUp(_:)))

        case "move-right":
            let offset =
                snapshotText(for: DebugSeedFixture.intro)?.count ?? DebugSeedFixture.introText.count
            focus(blockID: DebugSeedFixture.intro, offset: offset)
            renderAndSyncSurface(makeFirstResponder: true)
            _ = handleNativeCommand(#selector(NSResponder.moveRight(_:)))

        case "move-left":
            focus(blockID: DebugSeedFixture.tail, offset: 0)
            renderAndSyncSurface(makeFirstResponder: true)
            _ = handleNativeCommand(#selector(NSResponder.moveLeft(_:)))

        case "unicode-navigation":
            replaceIntroText("A👨‍👩‍👧‍👦B", caretOffset: 1)
            _ = handleNativeCommand(#selector(NSResponder.moveRight(_:)))

        case "prefix-list":
            focus(blockID: DebugSeedFixture.intro, offset: 0)
            renderAndSyncSurface(makeFirstResponder: true)
            replaceActiveText("")
            insertTextThroughNativeSurface("-")
            insertTextThroughNativeSurface(" ")

        case "prefix-heading":
            focus(blockID: DebugSeedFixture.intro, offset: 0)
            renderAndSyncSurface(makeFirstResponder: true)
            replaceActiveText("")
            insertTextThroughNativeSurface("#")
            insertTextThroughNativeSurface(" ")

        case "native-insert":
            let offset =
                snapshotText(for: DebugSeedFixture.intro)?.count ?? DebugSeedFixture.introText.count
            focus(blockID: DebugSeedFixture.intro, offset: offset)
            renderAndSyncSurface(makeFirstResponder: true)
            insertTextThroughNativeSurface(" typed")

        case "shift-enter":
            focus(blockID: DebugSeedFixture.intro, offset: 5)
            renderAndSyncSurface(makeFirstResponder: true)
            _ = handleNativeCommand(#selector(NSResponder.insertLineBreak(_:)))

        case "enter-split":
            focus(blockID: DebugSeedFixture.intro, offset: 5)
            renderAndSyncSurface(makeFirstResponder: true)
            _ = handleNativeCommand(#selector(NSResponder.insertNewline(_:)))

        case "tail-enter-split":
            let offset = DebugSeedFixture.tailSplitPrefix.count
            focus(blockID: DebugSeedFixture.tail, offset: offset)
            renderAndSyncSurface(makeFirstResponder: true)
            _ = handleNativeCommand(#selector(NSResponder.insertNewline(_:)))

        case "backspace-merge":
            focus(blockID: DebugSeedFixture.tail, offset: 0)
            renderAndSyncSurface(makeFirstResponder: true)
            _ = handleNativeCommand(#selector(NSResponder.deleteBackward(_:)))

        case "soft-line-down":
            replaceIntroText("Alpha\nOmega", caretOffset: "Alpha\n".count)
            _ = handleNativeCommand(#selector(NSResponder.moveDown(_:)))

        case "scroll-down":
            renderAndSyncSurface(makeFirstResponder: false)
            let start = DebugScrollFixture.scrollDownStart
            let offset =
                snapshotText(for: start)?.count
                ?? DebugScrollFixture.text(for: DebugScrollFixture.scrollDownStartIndex).count
            focus(blockID: start, offset: offset)
            renderAndSyncSurface(makeFirstResponder: true)
            _ = handleNativeCommand(#selector(NSResponder.moveDown(_:)))

        case "scroll-up":
            renderAndSyncSurface(makeFirstResponder: false)
            scrollDocument(to: DebugScrollFixture.scrollUpStartY)
            focus(blockID: DebugScrollFixture.scrollUpStart, offset: 0)
            renderAndSyncSurface(makeFirstResponder: true)
            _ = handleNativeCommand(#selector(NSResponder.moveUp(_:)))

        default:
            click(blockID: DebugSeedFixture.intro, x: CGFloat(editorStyle.gutterWidth + 96))
            replaceActiveText(
                "This active native surface is editing one block. The inserted text is intentionally long enough to wrap across multiple lines, forcing this block height to grow and pushing every following passive block down in the layout snapshot."
            )
        }
        renderAndSyncSurface(makeFirstResponder: true)
    }

    // MARK: - Screenshot

    func writeScreenshot(to path: String) throws {
        guard let contentView = view.window?.contentView else {
            throw CocoaError(.fileNoSuchFile)
        }
        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        contentView.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    // MARK: - Scenario Assertions

    func assertScenarioState(_ scenario: String) throws {
        switch scenario {
        case "basic-use":
            try assertBasicUseScenario(scenario)

        case "click-todo", "move-down", "move-right":
            try assertActiveTextInput(
                blockID: DebugSeedFixture.todo,
                expectedText: DebugSeedFixture.todoText,
                scenario: scenario
            )

        case "click-tail":
            try assertActiveTextInput(
                blockID: DebugSeedFixture.tail,
                expectedText: DebugSeedFixture.tailText,
                scenario: scenario
            )

        case "native-insert":
            try assertActiveTextInput(
                blockID: DebugSeedFixture.intro,
                expectedText: DebugSeedFixture.introText + " typed",
                scenario: scenario
            )
            try assertActiveTextSelection(
                expectedLocation: (DebugSeedFixture.introText + " typed").count,
                scenario: scenario
            )

        case "unicode-navigation":
            try assertActiveTextInput(
                blockID: DebugSeedFixture.intro,
                expectedText: "A👨‍👩‍👧‍👦B",
                scenario: scenario
            )
            try assertActiveTextSelection(expectedLocation: 2, scenario: scenario)

        case "prefix-list":
            try assertActiveTextInput(
                blockID: DebugSeedFixture.intro,
                expectedText: "",
                scenario: scenario
            )
            try assertActiveTextSelection(
                expectedLocation: 0,
                scenario: scenario
            )
            try require(
                snapshotRenderedBlock(for: DebugSeedFixture.intro)?.kind == .unorderedListItem,
                "\(scenario): prefix shortcut did not convert intro block to unordered list"
            )

        case "prefix-heading":
            try assertActiveTextInput(
                blockID: DebugSeedFixture.intro,
                expectedText: "",
                scenario: scenario
            )
            try assertActiveTextSelection(
                expectedLocation: 0,
                scenario: scenario
            )
            try require(
                snapshotRenderedBlock(for: DebugSeedFixture.intro)?.kind == .heading(level: .h1),
                "\(scenario): prefix shortcut did not convert intro block to heading"
            )

        case "enter-split":
            try assertActiveTextInput(
                expectedText: String(DebugSeedFixture.introText.dropFirst(5)),
                scenario: scenario
            )
            try require(
                snapshotText(for: DebugSeedFixture.intro)
                    == String(DebugSeedFixture.introText.prefix(5)),
                "\(scenario): original intro text was not split at expected offset"
            )

        case "tail-enter-split":
            try assertActiveTextInput(
                expectedText: DebugSeedFixture.tailSplitSuffix,
                scenario: scenario
            )
            try require(
                snapshotText(for: DebugSeedFixture.tail)
                    == DebugSeedFixture.tailSplitPrefix,
                "\(scenario): original tail text was not split at expected offset"
            )

        case "scroll-down":
            try assertActiveTextInput(
                blockID: DebugScrollFixture.scrollDownTarget,
                expectedText: DebugScrollFixture.text(
                    for: DebugScrollFixture.scrollDownTargetIndex),
                scenario: scenario
            )
            try require(
                currentViewport().scrollY > 0,
                "\(scenario): viewport did not scroll down after moving past visible bottom"
            )

        case "scroll-up":
            try assertActiveTextInput(
                blockID: DebugScrollFixture.scrollUpTarget,
                expectedText: DebugScrollFixture.text(for: DebugScrollFixture.scrollUpTargetIndex),
                scenario: scenario
            )
            try require(
                currentViewport().scrollY < DebugScrollFixture.scrollUpStartY,
                "\(scenario): viewport did not scroll up after moving past visible top"
            )

        case "text-drag-selection":
            try assertActiveTextInput(
                blockID: DebugSeedFixture.intro,
                expectedText: DebugSeedFixture.introText,
                scenario: scenario
            )
            try assertNonEmptyActiveTextSelection(
                blockID: DebugSeedFixture.intro,
                scenario: scenario
            )

        case "text-drag-clamp-to-block":
            try assertActiveTextInput(
                blockID: DebugSeedFixture.intro,
                expectedText: DebugSeedFixture.introText,
                scenario: scenario
            )
            try assertNonEmptyActiveTextSelection(
                blockID: DebugSeedFixture.intro,
                scenario: scenario
            )

        case "double-click-word-selection":
            try assertActiveTextInput(
                blockID: DebugSeedFixture.intro,
                expectedText: DebugSeedFixture.introText,
                scenario: scenario
            )
            try assertPartialActiveTextSelection(
                blockID: DebugSeedFixture.intro,
                scenario: scenario
            )

        case "double-click-block-text-selection":
            try assertActiveTextInput(
                blockID: DebugSeedFixture.intro,
                expectedText: DebugSeedFixture.introText,
                scenario: scenario
            )
            try assertActiveTextSelection(
                expectedRange: SlopadEngine.TextRange(0, DebugSeedFixture.introText.count),
                scenario: scenario
            )

        case "drag-reorder":
            try require(
                snapshotRootBlockIDs() == [
                    DebugSeedFixture.title,
                    DebugSeedFixture.code,
                    DebugSeedFixture.intro,
                    DebugSeedFixture.todo,
                    DebugSeedFixture.tail,
                ],
                "\(scenario): root order did not move selected blocks after code"
            )
            try require(
                snapshot?.blockDragState == nil,
                "\(scenario): block drag state was not cleared after drop"
            )
            guard let snapshot, case .blocks(let selection) = snapshot.selection else {
                throw DebugScenarioAssertionError(
                    message: "\(scenario): expected block selection after drop")
            }
            try require(
                selection.blockIDs == [DebugSeedFixture.intro, DebugSeedFixture.todo],
                "\(scenario): selection did not remain on moved blocks"
            )

        default:
            return
        }
    }

    private func assertActiveTextInput(
        expectedText: String,
        scenario: String
    ) throws {
        let activeInput = try require(
            snapshot?.activeTextInput,
            "\(scenario): missing active text input"
        )
        let request = activeInput.renderDescriptor.measureRequest
        try assertActiveTextInput(
            blockID: request.blockID,
            expectedText: expectedText,
            scenario: scenario
        )
    }

    private func assertActiveTextInput(
        blockID: BlockID,
        expectedText: String,
        scenario: String
    ) throws {
        let activeInput = try require(
            snapshot?.activeTextInput,
            "\(scenario): missing active text input selection=\(String(describing: snapshot?.selection)) viewport=\(currentViewport()) visible=\(snapshot?.visibleBlocks.map { $0.id.rawValue } ?? [])"
        )
        let request = activeInput.renderDescriptor.measureRequest
        try require(
            request.blockID == blockID,
            "\(scenario): active block \(request.blockID.rawValue) != \(blockID.rawValue)"
        )
        try require(
            request.text == expectedText,
            "\(scenario): descriptor text \(request.text.debugDescription) != \(expectedText.debugDescription)"
        )
        let documentText = snapshotText(for: blockID)
        try require(
            documentText == expectedText,
            "\(scenario): document text \((documentText ?? "nil").debugDescription) != \(expectedText.debugDescription)"
        )
        try require(
            activeNativeText == expectedText,
            "\(scenario): native surface text \(activeNativeText.debugDescription) != \(expectedText.debugDescription)"
        )
    }

    private func assertActiveTextSelection(expectedLocation: Int, scenario: String) throws {
        let activeInput = try require(
            snapshot?.activeTextInput,
            "\(scenario): missing active text input"
        )
        try require(
            activeInput.selectedRange == TextRange.point(expectedLocation),
            "\(scenario): descriptor selected range \(activeInput.selectedRange) != \(TextRange.point(expectedLocation))"
        )
        let expectedNativeRange = TextRange.point(expectedLocation)
            .textKitNSRange(in: activeNativeText)
        try require(
            activeNativeSelectedRange == expectedNativeRange,
            "\(scenario): native selected range \(activeNativeSelectedRange) != \(expectedNativeRange)"
        )
    }

    private func assertActiveTextSelection(
        expectedRange: SlopadEngine.TextRange,
        scenario: String
    ) throws {
        let activeInput = try require(
            snapshot?.activeTextInput,
            "\(scenario): missing active text input"
        )
        try require(
            activeInput.selectedRange == expectedRange,
            "\(scenario): descriptor selected range \(activeInput.selectedRange) != \(expectedRange)"
        )
        let expectedNativeRange = expectedRange.textKitNSRange(in: activeNativeText)
        try require(
            activeNativeSelectedRange == expectedNativeRange,
            "\(scenario): native selected range \(activeNativeSelectedRange) != \(expectedNativeRange)"
        )
    }

    private func assertNonEmptyActiveTextSelection(blockID: BlockID, scenario: String) throws {
        let activeInput = try require(
            snapshot?.activeTextInput,
            "\(scenario): missing active text input"
        )
        let request = activeInput.renderDescriptor.measureRequest
        try require(
            request.blockID == blockID,
            "\(scenario): active block \(request.blockID.rawValue) != \(blockID.rawValue)"
        )
        try require(
            !activeInput.selectedRange.isEmpty,
            "\(scenario): expected non-empty descriptor selected range"
        )
        try require(
            activeNativeSelectedRange.length > 0,
            "\(scenario): expected non-empty native selected range"
        )
        guard let snapshot, case .text(let textSelection) = snapshot.selection,
            textSelection.isSingleBlock
        else {
            throw DebugScenarioAssertionError(
                message: "\(scenario): expected single-block text selection"
            )
        }
    }

    private func assertPartialActiveTextSelection(blockID: BlockID, scenario: String) throws {
        let activeInput = try require(
            snapshot?.activeTextInput,
            "\(scenario): missing active text input"
        )
        try assertNonEmptyActiveTextSelection(blockID: blockID, scenario: scenario)
        let request = activeInput.renderDescriptor.measureRequest
        try require(
            activeInput.selectedRange != SlopadEngine.TextRange(0, request.text.count),
            "\(scenario): expected partial text selection"
        )
    }

    private func assertBasicUseScenario(_ scenario: String) throws {
        let visibleBlocks = snapshot?.visibleBlocks ?? []
        try require(
            visibleBlocks.count == 2,
            "\(scenario): expected 2 visible blocks, got \(visibleBlocks.count)"
        )
        try require(
            visibleBlocks[0].id == BasicUseFixture.title,
            "\(scenario): first block is not the README title block"
        )
        try require(
            visibleBlocks[0].kind == .heading(level: .h1),
            "\(scenario): title block is not h1"
        )
        try require(
            visibleBlocks[0].textRender.measureRequest.text == BasicUseFixture.titleText,
            "\(scenario): title text did not match README basic use"
        )
        try require(
            visibleBlocks[1].kind == .paragraph,
            "\(scenario): second block is not paragraph"
        )
        try require(
            visibleBlocks[1].textRender.measureRequest.text == BasicUseFixture.bodyText,
            "\(scenario): body text did not match README basic use"
        )
        try assertActiveTextInput(
            blockID: BasicUseFixture.title,
            expectedText: BasicUseFixture.titleText,
            scenario: scenario
        )
        try assertActiveTextSelection(expectedLocation: 0, scenario: scenario)
    }

    private func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw DebugScenarioAssertionError(message: message) }
        return value
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw DebugScenarioAssertionError(message: message) }
    }

    // MARK: - Debug Drawing

    func drawDebugHUD(_ snapshot: EditorSessionSnapshot) {
        let compositionText =
            snapshot.composition.map { " composition \($0.blockID.rawValue)" } ?? ""
        let viewport = currentViewport()
        let viewportHeight = Int(round(viewport.height))
        let viewportWidth = Int(round(viewport.width))
        let activeID =
            snapshot.activeTextInput?.renderDescriptor.measureRequest.blockID.rawValue ?? "none"
        let lines = [
            debugHUDRevisionLine(),
            "viewport(width=\(viewportWidth), height=\(viewportHeight))",
            "visibleBlock=\(snapshot.visibleBlocks.count)  totalHeight=\(Int(snapshot.totalHeight))  active=\(activeID)\(compositionText)",
        ]
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .backgroundColor: NSColor.windowBackgroundColor.withAlphaComponent(0.86),
        ]
        let visibleBounds = scrollView.contentView.bounds
        let lineSizes = lines.map { ($0 as NSString).size(withAttributes: attributes) }
        let lineHeight = ceil(lineSizes.map(\.height).max() ?? 14)
        let textSize = NSSize(
            width: ceil(lineSizes.map(\.width).max() ?? 0),
            height: lineHeight * CGFloat(lines.count)
        )
        let textRect = CGRect(
            x: visibleBounds.minX + 12,
            y: visibleBounds.maxY - ceil(textSize.height) - 10,
            width: min(ceil(textSize.width), visibleBounds.width - 24),
            height: ceil(textSize.height)
        )
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(
                in: CGRect(
                    x: textRect.minX,
                    y: textRect.minY + CGFloat(index) * lineHeight,
                    width: textRect.width,
                    height: lineHeight
                ),
                withAttributes: attributes
            )
        }

        for rendered in snapshot.visibleBlocks {
            let label =
                "\(rendered.id.rawValue) y=\(Int(rendered.frame.y)) h=\(Int(rendered.frame.height))"
            label.draw(
                in: CGRect(
                    x: CGFloat(editorStyle.gutterWidth) + 8, y: CGFloat(rendered.frame.y) + 2,
                    width: 260, height: 14),
                withAttributes: attributes
            )
        }
    }

    private func debugHUDRevisionLine() -> String {
        guard let comparison = debugHUDRevisionComparison else {
            return "rev(doc=? comp=? style=? width=initial visible=initial)"
        }
        return [
            "rev(doc=\(comparison.documentRevision)",
            "comp=\(comparison.compositionRevision)",
            "textLayout=\(comparison.textLayoutRevision)",
            "width=\(debugHUDChangeLabel(comparison.widthChanged, comparison: comparison))",
            "visible=\(debugHUDChangeLabel(comparison.visibleSequenceChanged, comparison: comparison)))",
        ].joined(separator: " ")
    }

    private func debugHUDChangeLabel(
        _ changed: Bool,
        comparison: EditorSnapshotRevisionComparison
    ) -> String {
        guard comparison.hasPreviousRevision else { return "initial" }
        return changed ? "changed" : "same"
    }

    // MARK: - Scenario Helpers

    private func click(blockID: BlockID, x: CGFloat) {
        renderAndSyncSurface(makeFirstResponder: false)
        guard
            let rendered = snapshot?.visibleBlocks.first(where: { $0.id == blockID })
        else { return }
        handleMouseDown(
            documentPoint: CGPoint(
                x: x,
                y: CGFloat(rendered.frame.y + rendered.frame.height * 0.5)
            )
        )
    }

    private func dragBlockSelection(from anchorID: BlockID, to focusID: BlockID, x: CGFloat) {
        renderAndSyncSurface(makeFirstResponder: false)
        guard
            let anchor = snapshot?.visibleBlocks.first(where: { $0.id == anchorID }),
            let focus = snapshot?.visibleBlocks.first(where: { $0.id == focusID })
        else { return }
        handleMouseDown(
            documentPoint: CGPoint(
                x: x,
                y: CGFloat(anchor.frame.y + anchor.frame.height * 0.5)
            )
        )
        handleMouseDragged(
            documentPoint: CGPoint(
                x: x,
                y: CGFloat(focus.frame.y + focus.frame.height * 0.5)
            )
        )
        handleMouseUp(
            documentPoint: CGPoint(
                x: x,
                y: CGFloat(focus.frame.y + focus.frame.height * 0.5)
            )
        )
    }

    private func dragTextSelection(
        in blockID: BlockID,
        fromTextX: CGFloat,
        toTextX: CGFloat
    ) {
        renderAndSyncSurface(makeFirstResponder: false)
        guard let rendered = snapshot?.visibleBlocks.first(where: { $0.id == blockID })
        else { return }
        let textFrame = rendered.textRender.frame
        let y = CGFloat(textFrame.y + min(10, max(4, textFrame.height * 0.5)))
        let startPoint = CGPoint(x: CGFloat(textFrame.x) + fromTextX, y: y)
        let endPoint = CGPoint(x: CGFloat(textFrame.x) + toTextX, y: y)
        handleMouseDown(documentPoint: startPoint)
        handleMouseDragged(documentPoint: endPoint)
        handleMouseUp(documentPoint: endPoint)
    }

    private func dragTextSelectionAcrossBlocks(from anchorID: BlockID, to focusID: BlockID) {
        renderAndSyncSurface(makeFirstResponder: false)
        guard
            let anchor = snapshot?.visibleBlocks.first(where: { $0.id == anchorID }),
            let focus = snapshot?.visibleBlocks.first(where: { $0.id == focusID })
        else { return }
        let anchorTextFrame = anchor.textRender.frame
        let startPoint = CGPoint(
            x: CGFloat(anchorTextFrame.x) + 4,
            y: CGFloat(anchorTextFrame.y + min(10, max(4, anchorTextFrame.height * 0.5)))
        )
        let focusPoint = CGPoint(
            x: CGFloat(anchorTextFrame.x) + 260,
            y: CGFloat(focus.frame.y + focus.frame.height * 0.5)
        )
        handleMouseDown(documentPoint: startPoint)
        handleMouseDragged(documentPoint: focusPoint)
        handleMouseUp(documentPoint: focusPoint)
    }

    private func doubleClickText(in blockID: BlockID, textX: CGFloat) {
        renderAndSyncSurface(makeFirstResponder: false)
        guard let rendered = snapshot?.visibleBlocks.first(where: { $0.id == blockID })
        else { return }
        let textFrame = rendered.textRender.frame
        let point = CGPoint(
            x: CGFloat(textFrame.x) + textX,
            y: CGFloat(textFrame.y + min(10, max(4, textFrame.height * 0.5)))
        )
        handleMouseDoubleClick(documentPoint: point)
    }

    private func clickText(in blockID: BlockID, textX: CGFloat) {
        renderAndSyncSurface(makeFirstResponder: false)
        guard let rendered = snapshot?.visibleBlocks.first(where: { $0.id == blockID })
        else { return }
        let textFrame = rendered.textRender.frame
        let point = CGPoint(
            x: CGFloat(textFrame.x) + textX,
            y: CGFloat(textFrame.y + min(10, max(4, textFrame.height * 0.5)))
        )
        handleMouseDown(documentPoint: point)
    }

    private func dragSelectedBlocks(from sourceID: BlockID, toAfter targetID: BlockID, x: CGFloat) {
        renderAndSyncSurface(makeFirstResponder: false)
        guard
            let source = snapshot?.visibleBlocks.first(where: { $0.id == sourceID }),
            let target = snapshot?.visibleBlocks.first(where: { $0.id == targetID })
        else { return }
        let startPoint = CGPoint(
            x: x,
            y: CGFloat(source.frame.y + source.frame.height * 0.5)
        )
        let targetPoint = CGPoint(
            x: x,
            y: CGFloat(target.frame.y + target.frame.height * 0.75)
        )
        handleMouseDown(documentPoint: startPoint)
        handleMouseDragged(documentPoint: targetPoint)
        handleMouseUp(documentPoint: targetPoint)
    }

    private func insertTextThroughNativeSurface(_ text: String) {
        insertTextFromNativeSurface(
            text,
            replacementRange: activeNativeSelectedRange
        )
    }

    private func replaceIntroText(_ text: String, caretOffset: Int) {
        focus(blockID: DebugSeedFixture.intro, offset: 0)
        renderAndSyncSurface(makeFirstResponder: true)
        replaceActiveText(text)
        focus(blockID: DebugSeedFixture.intro, offset: caretOffset)
        renderAndSyncSurface(makeFirstResponder: true)
    }

    private func simulateComposition(text: String) {
        let selectedRange = activeNativeSelectedRange
        setMarkedTextFromNativeSurface(
            text,
            selectedRange: NSRange(location: text.utf16.count, length: 0),
            replacementRange: selectedRange
        )
        renderCanvasPreservingNativeSurface()
    }

    private func simulateMarkedTextCallback(text: String, replacementRange: NSRange) {
        setMarkedTextFromNativeSurface(
            text,
            selectedRange: NSRange(location: text.utf16.count, length: 0),
            replacementRange: replacementRange
        )
        renderCanvasPreservingNativeSurface()
    }

    private func shortRevisionID(_ revision: Int) -> String {
        let truncated = UInt32(truncatingIfNeeded: UInt(bitPattern: revision))
        return String(format: "%08X", truncated)
    }

}

private enum BasicUseFixture {
    static let title = BlockID("title")
    static let titleText = "Slopad"
    static let bodyText = "Hello world."

    static func makeBlocks() -> [EditorBlockInput] {
        [
            EditorBlockInput(
                id: title,
                kind: .heading(level: .h1),
                content: BlockContent(text: titleText)
            ),
            EditorBlockInput(
                kind: .paragraph,
                content: BlockContent(text: bodyText)
            ),
        ]
    }
}

private enum DebugSeedFixture {
    static let title = BlockID()
    static let intro = BlockID()
    static let todo = BlockID()
    static let code = BlockID()
    static let tail = BlockID()

    static let titleText = "Slopad AppKit using TextKit2"
    static let introText =
        "Click this paragraph, type, and watch the native surface route editing while passive blocks stay rendered."
    static let todoText =
        "Gutter hit region uses an image and selects the block without activating text editing."
    static let codeText = "let surface = SlopadNativeBlockSurface()"
    static let tailText =
        "This lower block should visibly move down when the active paragraph wraps onto more lines."
    static let tailSplitPrefix = "This lower block should visibly move down wh"
    static let tailSplitSuffix = String(tailText.dropFirst(tailSplitPrefix.count))

    static func makeBlocks() -> [EditorBlockInput] {
        [
            EditorBlockInput(
                id: title,
                kind: .heading(level: .h1),
                content: BlockContent(text: titleText)
            ),
            EditorBlockInput(
                id: intro,
                kind: .paragraph,
                content: BlockContent(text: introText)
            ),
            EditorBlockInput(
                id: todo,
                kind: .todo(isChecked: false),
                content: BlockContent(text: todoText)
            ),
            EditorBlockInput(
                id: code,
                kind: .codeBlock(language: "swift"),
                content: BlockContent(text: codeText)
            ),
            EditorBlockInput(
                id: tail,
                kind: .paragraph,
                content: BlockContent(text: tailText)
            ),
        ]
    }
}

private enum DebugScrollFixture {
    static let blocks = (0..<28).map { _ in BlockID() }
    static let scrollDownStartIndex = 10
    static let scrollDownTargetIndex = 11
    static let scrollUpStartIndex = 6
    static let scrollUpTargetIndex = 5
    static let scrollUpStartY = 260.0

    static var scrollDownStart: BlockID {
        blocks[scrollDownStartIndex]
    }

    static var scrollDownTarget: BlockID {
        blocks[scrollDownTargetIndex]
    }

    static var scrollUpStart: BlockID {
        blocks[scrollUpStartIndex]
    }

    static var scrollUpTarget: BlockID {
        blocks[scrollUpTargetIndex]
    }

    static func text(for index: Int) -> String {
        "Scroll row \(index)\nThe second line makes this row tall enough for reveal checks."
    }

    static func makeBlocks() -> [EditorBlockInput] {
        blocks.enumerated().map { index, blockID in
            EditorBlockInput(
                id: blockID,
                kind: .paragraph,
                content: BlockContent(text: text(for: index))
            )
        }
    }
}

private struct DebugScenarioAssertionError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}
