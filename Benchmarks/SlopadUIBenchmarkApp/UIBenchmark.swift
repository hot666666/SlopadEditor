import AppKit
import Foundation
import SlopadAppKitTextKit
import SlopadAppKitUI
import SlopadEngine

@MainActor
struct UIBenchmarkOptions {
    var scenario: String
    var blockCount: Int
    var activeTextLength: Int?
    var frameCount: Int
    var outputPath: String
    var subtreeNodeCount: Int?
}

@MainActor
private enum UIBenchmarkScenario: String {
    case scroll
    case composition
    case mixed
    case nativeInsert = "native-insert"
    case heightExpansion = "height-expansion"
    case blockSelection = "block-selection"
    case blockReorder = "block-reorder"
    case subtreeDelete = "subtree-delete"
    case subtreeReorder = "subtree-reorder"
    case styleChange = "style-change"
    case unicodeNavigation = "unicode-navigation"

    init(argument: String) {
        self = UIBenchmarkScenario(rawValue: argument) ?? .scroll
    }

    var usesSubtreeFixture: Bool {
        switch self {
        case .subtreeDelete, .subtreeReorder:
            return true
        case .scroll, .nativeInsert, .composition, .heightExpansion, .blockSelection,
            .blockReorder, .styleChange, .unicodeNavigation, .mixed:
            return false
        }
    }

    var requiresFreshDocumentPerFrame: Bool {
        switch self {
        case .subtreeDelete:
            return true
        case .scroll, .nativeInsert, .composition, .heightExpansion, .blockSelection,
            .blockReorder, .subtreeReorder, .styleChange, .unicodeNavigation, .mixed:
            return false
        }
    }
}

@MainActor
enum UIBenchmarkFixture {
    static func makeBlocks(count: Int) -> (blocks: [EditorBlockInput], firstBlockID: BlockID) {
        makeBlocks(count: count, scenario: .scroll)
    }

    fileprivate static func makeBlocks(
        count: Int,
        scenario: UIBenchmarkScenario,
        subtreeNodeCount: Int? = nil,
        activeTextLength: Int? = nil
    ) -> (blocks: [EditorBlockInput], firstBlockID: BlockID) {
        let blockCount = max(2, count)
        let targetIndex = benchmarkTargetIndex(blockCount: blockCount)
        let resolvedSubtreeNodeCount = self.subtreeNodeCount(
            for: blockCount,
            override: subtreeNodeCount
        )
        var blocks: [EditorBlockInput] = []
        blocks.reserveCapacity(blockCount)
        var firstBlockID: BlockID?

        for index in 0..<blockCount {
            let blockID = blockID(index)
            let parentID =
                scenario.usesSubtreeFixture
                ? subtreeParentID(
                    for: index,
                    blockCount: blockCount,
                    subtreeNodeCount: resolvedSubtreeNodeCount
                )
                : nil
            if firstBlockID == nil {
                firstBlockID = blockID
            }
            blocks.append(
                EditorBlockInput(
                    id: blockID,
                    parentID: parentID,
                    kind: kind(for: index),
                    content: BlockContent(
                        text: scenario == .unicodeNavigation
                            ? unicodeNavigationText(
                                for: index,
                                length: index == targetIndex ? activeTextLength : nil
                            )
                            : text(for: index)
                    )
                )
            )
        }

        return (blocks, firstBlockID ?? BlockID())
    }

    static func blockID(_ index: Int) -> BlockID {
        BlockID("ui-bench-\(index)")
    }

    static func text(for index: Int) -> String {
        let suffix =
            index.isMultiple(of: 11)
            ? " This row is deliberately longer so TextKit wraps it and the visible pass has mixed heights."
            : ""
        return
            "Benchmark block \(index). Native UI render path measures real AppKit drawing and scroll invalidation.\(suffix)"
    }

    static func unicodeNavigationText(for index: Int, length: Int? = nil) -> String {
        let base = "한글단어와 punctuation \(index) — English שלום עולם 👨‍👩‍👧‍👦 e\u{301} 끝"
        guard let length else { return base }

        let targetLength = max(1, length)
        let repeatedUnit = Array(base + " ")
        var characters: [Character] = []
        characters.reserveCapacity(targetLength)
        while characters.count < targetLength {
            characters.append(contentsOf: repeatedUnit.prefix(targetLength - characters.count))
        }
        return String(characters)
    }

    static func subtreeNodeCount(for blockCount: Int) -> Int {
        min(max(6, blockCount / 20), 200)
    }

    static func subtreeNodeCount(for blockCount: Int, override: Int?) -> Int {
        guard let override else { return subtreeNodeCount(for: blockCount) }
        return min(max(1, override), blockCount)
    }

    static func subtreeRootIndex(blockCount: Int, subtreeNodeCount: Int? = nil) -> Int {
        let subtreeCount = self.subtreeNodeCount(for: blockCount, override: subtreeNodeCount)
        return max(1, min(blockCount - 2, blockCount / 2 - subtreeCount / 2))
    }

    static func subtreeLastIndex(blockCount: Int, subtreeNodeCount: Int? = nil) -> Int {
        let rootIndex = subtreeRootIndex(blockCount: blockCount, subtreeNodeCount: subtreeNodeCount)
        let subtreeCount = self.subtreeNodeCount(for: blockCount, override: subtreeNodeCount)
        return min(blockCount - 1, rootIndex + subtreeCount - 1)
    }

    static func subtreeBeforeTargetIndex(blockCount: Int, subtreeNodeCount: Int? = nil) -> Int {
        max(0, subtreeRootIndex(blockCount: blockCount, subtreeNodeCount: subtreeNodeCount) - 1)
    }

    static func subtreeAfterTargetIndex(blockCount: Int, subtreeNodeCount: Int? = nil) -> Int {
        min(
            blockCount - 1,
            subtreeLastIndex(blockCount: blockCount, subtreeNodeCount: subtreeNodeCount) + 12
        )
    }

    private static func kind(for index: Int) -> BlockKind {
        if index.isMultiple(of: 97) {
            return .heading(level: .h2)
        }
        if index.isMultiple(of: 17) {
            return .todo(isChecked: index.isMultiple(of: 34))
        }
        if index.isMultiple(of: 31) {
            return .unorderedListItem
        }
        return .paragraph
    }

    private static func benchmarkTargetIndex(blockCount: Int) -> Int {
        max(1, min(blockCount - 2, blockCount / 2))
    }

    private static func subtreeParentID(
        for index: Int,
        blockCount: Int,
        subtreeNodeCount: Int
    ) -> BlockID? {
        let rootIndex = subtreeRootIndex(
            blockCount: blockCount,
            subtreeNodeCount: subtreeNodeCount
        )
        let subtreeRange =
            rootIndex..<(subtreeLastIndex(
                blockCount: blockCount,
                subtreeNodeCount: subtreeNodeCount
            ) + 1)
        if index == rootIndex || !subtreeRange.contains(index) {
            return nil
        }
        if (index - rootIndex) % 4 == 1 {
            return blockID(rootIndex)
        }
        return blockID(index - 1)
    }
}

@MainActor
final class UIBenchmarkHost {
    // MARK: - Dependencies

    let editorViewController: AppKitEditorViewController

    // MARK: - State

    var uiBenchmarkRecorder: UIBenchmarkRecorder?

    // MARK: - Init

    init(
        blockCount: Int,
        scenario: String,
        subtreeNodeCount: Int?,
        activeTextLength: Int?
    ) {
        let resolvedScenario = UIBenchmarkScenario(argument: scenario)
        let editorStyle = TextKitEditorStyle(
            languageIdentifier: resolvedScenario == .unicodeNavigation ? "ko-KR" : nil
        )
        let fixture = UIBenchmarkFixture.makeBlocks(
            count: blockCount,
            scenario: resolvedScenario,
            subtreeNodeCount: subtreeNodeCount,
            activeTextLength: activeTextLength
        )
        editorViewController = AppKitEditorViewController(
            blocks: fixture.blocks,
            selection: .caret(blockID: fixture.firstBlockID, offset: 0),
            style: editorStyle,
            focusOnAppear: false
        )
        editorViewController.onDrawCompleted = { [weak self] dirtyRect, durationNanoseconds in
            self?.uiBenchmarkRecorder?.recordDraw(
                durationNanoseconds: durationNanoseconds,
                dirtyRect: dirtyRect
            )
        }
    }

    // MARK: - AppKitUI Facade

    var session: EditorSession {
        editorViewController.session
    }

    var snapshot: EditorSessionSnapshot? {
        editorViewController.snapshot
    }

    var scrollView: NSScrollView {
        editorViewController.scrollView
    }

    var editorStyle: TextKitEditorStyle {
        editorViewController.editorStyle
    }

    func renderAndSyncSurface(
        makeFirstResponder: Bool,
        scrollSelectionIntoView: Bool = false
    ) {
        editorViewController.renderAndSyncSurface(
            makeFirstResponder: makeFirstResponder,
            scrollSelectionIntoView: scrollSelectionIntoView
        )
    }

    func currentViewport() -> EditorViewport {
        editorViewController.currentViewport()
    }

    func focus(blockID: BlockID, offset: Int) {
        _ = handleNativeInputEvent(
            .activeTextSelectionChanged(
                blockID: blockID,
                selectedRange: .point(offset)
            )
        )
    }

    @discardableResult
    func handleNativeInputEvent(_ inputEvent: EditorInputEvent) -> EditorUpdate? {
        editorViewController.handleInputWithoutRendering(inputEvent)
    }

    func resetDocument(blocks: [EditorBlockInput], selection: EditorSelection) {
        editorViewController.resetDocumentWithoutRendering(blocks: blocks, selection: selection)
    }

    func scrollDocument(to y: Double) {
        editorViewController.scrollDocumentWithoutRendering(to: y)
    }

    func updateEditorStyle(_ style: TextKitEditorStyle) {
        editorViewController.updateEditorStyle(style)
    }

    fileprivate func resetUIBenchmarkDocument(
        blockCount: Int,
        scenario: UIBenchmarkScenario,
        subtreeNodeCount: Int?,
        activeTextLength: Int?
    ) {
        let fixture = UIBenchmarkFixture.makeBlocks(
            count: blockCount,
            scenario: scenario,
            subtreeNodeCount: subtreeNodeCount,
            activeTextLength: activeTextLength
        )
        resetDocument(
            blocks: fixture.blocks,
            selection: .caret(blockID: fixture.firstBlockID, offset: 0)
        )
    }
}

@MainActor
final class UIBenchmarkRecorder {
    private(set) var samples: [UIBenchmarkFrameSample] = []
    private var currentSample: UIBenchmarkFrameSample?

    func beginFrame(index: Int, scrollY: Double) {
        currentSample = UIBenchmarkFrameSample(frame: index, scrollY: scrollY)
    }

    func recordRender(durationNanoseconds: UInt64, visibleRenderedBlockCount: Int) {
        currentSample?.renderAndSyncNanoseconds = durationNanoseconds
        currentSample?.visibleRenderedBlockCount = visibleRenderedBlockCount
    }

    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        func recordRender(
            durationNanoseconds: UInt64,
            visibleRenderedBlockCount: Int,
            metrics: EditorSessionBenchmarkMetrics
        ) {
            currentSample?.renderAndSyncNanoseconds = durationNanoseconds
            currentSample?.layoutMode = metrics.layoutMode
            currentSample?.visibleOrderEntryCount = metrics.visibleOrderEntryCount
            currentSample?.visibleRenderedBlockCount = visibleRenderedBlockCount
            currentSample?.layoutInputBlockCount = metrics.layoutInputBlockCount
            currentSample?.layoutOutputBlockCount = metrics.layoutOutputBlockCount
            currentSample?.cacheHitCount = metrics.cacheHitCount
            currentSample?.cacheMissCount = metrics.cacheMissCount
            currentSample?.heightIndexRebuildCount = metrics.heightIndexRebuildCount
            currentSample?.heightIndexInsertCount = metrics.heightIndexInsertCount
            currentSample?.heightIndexRemoveCount = metrics.heightIndexRemoveCount
            currentSample?.heightIndexMoveCount = metrics.heightIndexMoveCount
            currentSample?.heightIndexUpdateHeightCount =
                metrics.heightIndexUpdateHeightCount
        }
    #endif

    func recordDisplay(durationNanoseconds: UInt64) {
        currentSample?.displayNanoseconds = durationNanoseconds
    }

    func recordOperation(name: String, durationNanoseconds: UInt64) {
        currentSample?.operation = name
        currentSample?.operationNanoseconds = durationNanoseconds
    }

    func recordDraw(durationNanoseconds: UInt64, dirtyRect: NSRect) {
        currentSample?.drawNanoseconds += durationNanoseconds
        currentSample?.drawCount += 1
        currentSample?.dirtyArea += Double(dirtyRect.width * dirtyRect.height)
    }

    func finishFrame(totalNanoseconds: UInt64) {
        currentSample?.frameNanoseconds = totalNanoseconds
        if let currentSample {
            samples.append(currentSample)
        }
        currentSample = nil
    }

    func csv(blockCount: Int, scenario: String) -> String {
        let rows =
            [Self.csvHeader]
            + samples.map { $0.csvRow(blockCount: blockCount, scenario: scenario) }
        return rows.joined(separator: "\n") + "\n"
    }

    func summary(blockCount: Int, scenario: String) -> String {
        let frameMilliseconds = samples.map { $0.frameMilliseconds }.sorted()
        guard !frameMilliseconds.isEmpty else {
            return "SlopadUIBenchmarkApp UI benchmark produced no samples"
        }
        let averageMs = frameMilliseconds.reduce(0, +) / Double(frameMilliseconds.count)
        let p95Ms = percentile(95, in: frameMilliseconds)
        let operationMilliseconds = samples.map { $0.operationMilliseconds }
        let averageOperationMs =
            operationMilliseconds.isEmpty
            ? 0
            : operationMilliseconds.reduce(0, +) / Double(operationMilliseconds.count)
        let over16 = frameMilliseconds.filter { $0 > 16.67 }.count
        let over33 = frameMilliseconds.filter { $0 > 33.33 }.count
        let fps = averageMs > 0 ? 1000.0 / averageMs : 0
        return String(
            format:
                "SlopadUIBenchmarkApp UI benchmark scenario=%@ blocks=%d frames=%d avgFPS=%.1f avgFrameMs=%.3f p95FrameMs=%.3f avgOperationMs=%.3f over16ms=%d over33ms=%d",
            scenario,
            blockCount,
            samples.count,
            fps,
            averageMs,
            p95Ms,
            averageOperationMs,
            over16,
            over33
        )
    }

    private static let csvHeader = [
        "scenario",
        "blockCount",
        "frame",
        "scrollY",
        "operation",
        "operationMs",
        "frameMs",
        "renderAndSyncMs",
        "displayMs",
        "drawMs",
        "drawCount",
        "dirtyArea",
        "layoutMode",
        "visibleOrderEntryCount",
        "visibleRenderedBlockCount",
        "layoutInputBlockCount",
        "layoutOutputBlockCount",
        "cacheHitCount",
        "cacheMissCount",
        "heightIndexRebuildCount",
        "heightIndexInsertCount",
        "heightIndexRemoveCount",
        "heightIndexMoveCount",
        "heightIndexUpdateHeightCount",
    ].joined(separator: ",")

    private func percentile(_ percentile: Double, in sortedValues: [Double]) -> Double {
        guard let first = sortedValues.first else { return 0 }
        guard sortedValues.count > 1 else { return first }
        let position = (percentile / 100.0) * Double(sortedValues.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper {
            return sortedValues[lower]
        }
        let fraction = position - Double(lower)
        return sortedValues[lower] * (1 - fraction) + sortedValues[upper] * fraction
    }
}

struct UIBenchmarkFrameSample {
    var frame: Int
    var scrollY: Double
    var operation: String = "none"
    var operationNanoseconds: UInt64 = 0
    var frameNanoseconds: UInt64 = 0
    var renderAndSyncNanoseconds: UInt64 = 0
    var displayNanoseconds: UInt64 = 0
    var drawNanoseconds: UInt64 = 0
    var drawCount: Int = 0
    var dirtyArea: Double = 0
    var layoutMode: String = "unavailable"
    var visibleOrderEntryCount: Int = 0
    var visibleRenderedBlockCount: Int = 0
    var layoutInputBlockCount: Int = 0
    var layoutOutputBlockCount: Int = 0
    var cacheHitCount: Int = 0
    var cacheMissCount: Int = 0
    var heightIndexRebuildCount: Int = 0
    var heightIndexInsertCount: Int = 0
    var heightIndexRemoveCount: Int = 0
    var heightIndexMoveCount: Int = 0
    var heightIndexUpdateHeightCount: Int = 0

    var frameMilliseconds: Double {
        milliseconds(frameNanoseconds)
    }

    var operationMilliseconds: Double {
        milliseconds(operationNanoseconds)
    }

    func csvRow(blockCount: Int, scenario: String) -> String {
        [
            scenario,
            String(blockCount),
            String(frame),
            format(scrollY),
            operation,
            format(operationMilliseconds),
            format(milliseconds(frameNanoseconds)),
            format(milliseconds(renderAndSyncNanoseconds)),
            format(milliseconds(displayNanoseconds)),
            format(milliseconds(drawNanoseconds)),
            String(drawCount),
            format(dirtyArea),
            layoutMode,
            String(visibleOrderEntryCount),
            String(visibleRenderedBlockCount),
            String(layoutInputBlockCount),
            String(layoutOutputBlockCount),
            String(cacheHitCount),
            String(cacheMissCount),
            String(heightIndexRebuildCount),
            String(heightIndexInsertCount),
            String(heightIndexRemoveCount),
            String(heightIndexMoveCount),
            String(heightIndexUpdateHeightCount),
        ].map(csvEscape).joined(separator: ",")
    }

    private func milliseconds(_ nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000_000.0
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

@MainActor
enum UIBenchmarkRunner {
    static func run(
        window: NSWindow,
        viewController: UIBenchmarkHost,
        options: UIBenchmarkOptions
    ) throws {
        let recorder = UIBenchmarkRecorder()
        viewController.uiBenchmarkRecorder = recorder
        defer { viewController.uiBenchmarkRecorder = nil }

        let scenario = UIBenchmarkScenario(argument: options.scenario)
        viewController.renderAndSyncSurface(makeFirstResponder: false)
        viewController.scrollView.documentView?.displayIfNeeded()
        window.displayIfNeeded()
        if !scenario.requiresFreshDocumentPerFrame {
            prepare(scenario: scenario, options: options, viewController: viewController)
        }

        let frameCount = max(1, options.frameCount)
        for frame in 0..<frameCount {
            if scenario.requiresFreshDocumentPerFrame {
                viewController.resetUIBenchmarkDocument(
                    blockCount: options.blockCount,
                    scenario: scenario,
                    subtreeNodeCount: options.subtreeNodeCount,
                    activeTextLength: options.activeTextLength
                )
                prepare(scenario: scenario, options: options, viewController: viewController)
            }
            let scrollY = scrollY(
                forFrame: frame,
                frameCount: frameCount,
                scenario: scenario,
                viewController: viewController
            )
            setScrollY(scrollY, viewController: viewController)

            recorder.beginFrame(index: frame, scrollY: scrollY)
            let frameStart = DispatchTime.now().uptimeNanoseconds

            let operationStart = DispatchTime.now().uptimeNanoseconds
            let operation = performOperation(
                scenario: scenario,
                frame: frame,
                options: options,
                viewController: viewController
            )
            recorder.recordOperation(
                name: operation,
                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - operationStart
            )

            let renderStart = DispatchTime.now().uptimeNanoseconds
            viewController.renderAndSyncSurface(makeFirstResponder: false)
            let renderDuration = DispatchTime.now().uptimeNanoseconds - renderStart
            let visibleRenderedBlockCount = viewController.snapshot?.visibleBlocks.count ?? 0
            #if SLOPAD_BENCHMARK_INSTRUMENTATION
                recorder.recordRender(
                    durationNanoseconds: renderDuration,
                    visibleRenderedBlockCount: visibleRenderedBlockCount,
                    metrics: viewController.session.lastBenchmarkMetrics
                )
            #else
                recorder.recordRender(
                    durationNanoseconds: renderDuration,
                    visibleRenderedBlockCount: visibleRenderedBlockCount
                )
            #endif

            let displayStart = DispatchTime.now().uptimeNanoseconds
            viewController.scrollView.documentView?.displayIfNeeded()
            window.displayIfNeeded()
            recorder.recordDisplay(
                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - displayStart)

            recorder.finishFrame(
                totalNanoseconds: DispatchTime.now().uptimeNanoseconds - frameStart)
        }

        let csv = recorder.csv(blockCount: options.blockCount, scenario: options.scenario)
        try write(csv, to: options.outputPath)
        fputs(
            recorder.summary(blockCount: options.blockCount, scenario: options.scenario) + "\n",
            stderr)
    }

    private static func prepare(
        scenario: UIBenchmarkScenario,
        options: UIBenchmarkOptions,
        viewController: UIBenchmarkHost
    ) {
        guard scenario != .scroll else { return }
        let target = targetBlockID(blockCount: options.blockCount)
        centerBlock(target, viewController: viewController)

        switch scenario {
        case .nativeInsert, .composition, .heightExpansion, .unicodeNavigation, .mixed:
            let targetIndex = targetBlockIndex(blockCount: options.blockCount)
            viewController.focus(
                blockID: target,
                offset: scenario == .unicodeNavigation
                    ? UIBenchmarkFixture.unicodeNavigationText(
                        for: targetIndex,
                        length: options.activeTextLength
                    ).count
                    : UIBenchmarkFixture.text(for: targetIndex).count
            )
            viewController.renderAndSyncSurface(makeFirstResponder: true)

        case .blockSelection, .blockReorder, .subtreeDelete, .subtreeReorder, .styleChange:
            viewController.renderAndSyncSurface(makeFirstResponder: false)

        case .scroll:
            break
        }
    }

    private static func scrollY(
        forFrame frame: Int,
        frameCount: Int,
        scenario: UIBenchmarkScenario,
        viewController: UIBenchmarkHost
    ) -> Double {
        switch scenario {
        case .scroll, .mixed:
            break
        case .nativeInsert, .composition, .heightExpansion, .blockSelection, .blockReorder,
            .subtreeDelete, .subtreeReorder, .styleChange, .unicodeNavigation:
            return Double(viewController.scrollView.contentView.bounds.origin.y)
        }

        guard viewController.scrollView.documentView != nil else { return 0 }
        let visibleHeight = viewController.scrollView.contentView.bounds.height
        let documentHeight = viewController.scrollView.documentView?.frame.height ?? visibleHeight
        let maxY = max(0, documentHeight - visibleHeight)
        guard maxY > 0, frameCount > 1 else { return 0 }

        let progress = Double(frame) / Double(frameCount - 1)
        return Double(maxY) * progress
    }

    private static func performOperation(
        scenario: UIBenchmarkScenario,
        frame: Int,
        options: UIBenchmarkOptions,
        viewController: UIBenchmarkHost
    ) -> String {
        switch scenario {
        case .scroll:
            return "scroll"

        case .nativeInsert:
            insertText(frame: frame, options: options, viewController: viewController)
            return "insertText"

        case .composition:
            updateComposition(frame: frame, options: options, viewController: viewController)
            return frame == 0 ? "beginComposition" : "updateComposition"

        case .heightExpansion:
            expandHeight(frame: frame, options: options, viewController: viewController)
            return "heightExpansion"

        case .blockSelection:
            selectBlock(frame: frame, options: options, viewController: viewController)
            return "blockSelection"

        case .blockReorder:
            reorderBlock(frame: frame, options: options, viewController: viewController)
            return "blockReorder"

        case .subtreeDelete:
            deleteSubtree(options: options, viewController: viewController)
            return "subtreeDelete"

        case .subtreeReorder:
            reorderSubtree(frame: frame, options: options, viewController: viewController)
            return "subtreeReorder"

        case .styleChange:
            updateStyle(frame: frame, viewController: viewController)
            return "updateEditorStyle"

        case .unicodeNavigation:
            let viewport = viewController.currentViewport()
            if frame.isMultiple(of: 2) {
                _ = viewController.handleNativeInputEvent(
                    .command(.moveWordLeft(viewport: viewport))
                )
                return "moveWordLeft"
            }
            _ = viewController.handleNativeInputEvent(
                .command(.moveWordRight(viewport: viewport))
            )
            return "moveWordRight"

        case .mixed:
            switch frame % 6 {
            case 0:
                return "scroll"
            case 1:
                insertText(frame: frame, options: options, viewController: viewController)
                return "insertText"
            case 2:
                updateComposition(frame: frame, options: options, viewController: viewController)
                return "updateComposition"
            case 3:
                selectBlock(frame: frame, options: options, viewController: viewController)
                return "blockSelection"
            case 4:
                expandHeight(frame: frame, options: options, viewController: viewController)
                return "heightExpansion"
            default:
                reorderBlock(frame: frame, options: options, viewController: viewController)
                return "blockReorder"
            }
        }
    }

    private static func updateStyle(
        frame: Int,
        viewController: UIBenchmarkHost
    ) {
        let usesAlternateStyle = frame.isMultiple(of: 2)
        viewController.updateEditorStyle(
            TextKitEditorStyle(
                fontSize: usesAlternateStyle ? 16 : 15,
                lineHeightMultiple: usesAlternateStyle ? 1.3 : 1.25,
                gutterWidth: usesAlternateStyle ? 44 : 40,
                contentHorizontalPadding: usesAlternateStyle ? 16 : 14,
                blockIndentWidth: usesAlternateStyle ? 22 : 20
            )
        )
    }

    private static func insertText(
        frame: Int,
        options: UIBenchmarkOptions,
        viewController: UIBenchmarkHost
    ) {
        let target = targetBlockID(blockCount: options.blockCount)
        let text = frame.isMultiple(of: 12) ? " typed-\(frame)" : "x"
        if viewController.handleNativeInputEvent(.command(.insertText(text))) == nil {
            viewController.focus(blockID: target, offset: 0)
            _ = viewController.handleNativeInputEvent(.command(.insertText(text)))
        }
    }

    private static func updateComposition(
        frame: Int,
        options: UIBenchmarkOptions,
        viewController: UIBenchmarkHost
    ) {
        let target = targetBlockID(blockCount: options.blockCount)
        let replacementRange = TextRange(
            0,
            min(
                6,
                UIBenchmarkFixture.text(
                    for: targetBlockIndex(blockCount: options.blockCount)
                ).count))
        let text = "marked-\(frame % 10)"
        let event: EditorInputEvent =
            frame == 0
            ? .beginComposition(blockID: target, replacementRange: replacementRange, text: text)
            : .updateComposition(blockID: target, replacementRange: replacementRange, text: text)
        _ = viewController.handleNativeInputEvent(event)
    }

    private static func expandHeight(
        frame: Int,
        options: UIBenchmarkOptions,
        viewController: UIBenchmarkHost
    ) {
        let target = targetBlockID(blockCount: options.blockCount)
        let text =
            " height-expansion-\(frame) wraps enough text to invalidate this block and downstream y positions."
        if viewController.handleNativeInputEvent(.command(.insertText(text))) == nil {
            viewController.focus(blockID: target, offset: 0)
            _ = viewController.handleNativeInputEvent(.command(.insertText(text)))
        }
    }

    private static func selectBlock(
        frame: Int,
        options: UIBenchmarkOptions,
        viewController: UIBenchmarkHost
    ) {
        let blockID =
            frame.isMultiple(of: 2)
            ? targetBlockID(blockCount: options.blockCount)
            : secondaryBlockID(blockCount: options.blockCount)
        guard
            let point = blockPoint(
                blockID: blockID,
                x: Double(viewController.editorStyle.gutterWidth) * 0.5,
                yFraction: 0.5,
                viewController: viewController
            )
        else { return }
        _ = viewController.handleNativeInputEvent(
            .pointer(
                .selectBlock(
                    documentPoint: point,
                    region: .gutter,
                    viewport: viewController.currentViewport()
                )
            )
        )
    }

    private static func reorderBlock(
        frame: Int,
        options: UIBenchmarkOptions,
        viewController: UIBenchmarkHost
    ) {
        let source =
            frame.isMultiple(of: 2)
            ? targetBlockID(blockCount: options.blockCount)
            : secondaryBlockID(blockCount: options.blockCount)
        let target =
            frame.isMultiple(of: 2)
            ? secondaryBlockID(blockCount: options.blockCount)
            : targetBlockID(blockCount: options.blockCount)
        guard
            let startPoint = blockPoint(
                blockID: source,
                x: Double(viewController.editorStyle.gutterWidth) * 0.5,
                yFraction: 0.5,
                viewController: viewController
            ),
            let dropPoint = blockPoint(
                blockID: target,
                x: Double(viewController.editorStyle.gutterWidth) * 0.5,
                yFraction: 0.75,
                viewController: viewController
            )
        else { return }

        let viewport = viewController.currentViewport()
        _ = viewController.handleNativeInputEvent(
            .pointer(
                .selectBlock(
                    documentPoint: startPoint,
                    region: .gutter,
                    viewport: viewport
                )
            )
        )
        _ = viewController.handleNativeInputEvent(
            .pointer(.beginBlockDrag(documentPoint: startPoint, viewport: viewport))
        )
        _ = viewController.handleNativeInputEvent(
            .pointer(.endBlockDrag(documentPoint: dropPoint, viewport: viewport))
        )
    }

    private static func deleteSubtree(
        options: UIBenchmarkOptions,
        viewController: UIBenchmarkHost
    ) {
        guard selectSubtree(options: options, viewController: viewController) else { return }
        _ = viewController.handleNativeInputEvent(.command(.deleteBackward))
    }

    private static func reorderSubtree(
        frame: Int,
        options: UIBenchmarkOptions,
        viewController: UIBenchmarkHost
    ) {
        guard selectSubtree(options: options, viewController: viewController) else { return }
        let source = subtreeRootBlockID(
            blockCount: options.blockCount,
            subtreeNodeCount: options.subtreeNodeCount
        )
        let target =
            frame.isMultiple(of: 2)
            ? subtreeAfterTargetBlockID(
                blockCount: options.blockCount,
                subtreeNodeCount: options.subtreeNodeCount
            )
            : subtreeBeforeTargetBlockID(
                blockCount: options.blockCount,
                subtreeNodeCount: options.subtreeNodeCount
            )
        guard
            let startPoint = blockPoint(
                blockID: source,
                x: Double(viewController.editorStyle.gutterWidth) * 0.5,
                yFraction: 0.5,
                viewController: viewController
            ),
            let dropPoint = blockPoint(
                blockID: target,
                x: Double(viewController.editorStyle.gutterWidth) * 0.5,
                yFraction: 0.75,
                viewController: viewController
            )
        else { return }

        let viewport = viewController.currentViewport()
        _ = viewController.handleNativeInputEvent(
            .pointer(.beginBlockDrag(documentPoint: startPoint, viewport: viewport))
        )
        _ = viewController.handleNativeInputEvent(
            .pointer(.endBlockDrag(documentPoint: dropPoint, viewport: viewport))
        )
    }

    private static func selectSubtree(
        options: UIBenchmarkOptions,
        viewController: UIBenchmarkHost
    ) -> Bool {
        guard
            let anchor = hitResult(
                blockID: subtreeRootBlockID(
                    blockCount: options.blockCount,
                    subtreeNodeCount: options.subtreeNodeCount
                ),
                region: .gutter,
                viewController: viewController
            ),
            let focus = hitResult(
                blockID: subtreeLastBlockID(
                    blockCount: options.blockCount,
                    subtreeNodeCount: options.subtreeNodeCount
                ),
                region: .gutter,
                viewController: viewController
            )
        else {
            return false
        }
        return viewController.handleNativeInputEvent(
            .pointer(.selectBlockRange(anchor: anchor, focus: focus))
        ) != nil
    }

    private static func hitResult(
        blockID: BlockID,
        region: BlockHitRegion,
        viewController: UIBenchmarkHost
    ) -> BlockHitTestResult? {
        guard
            let point = blockPoint(
                blockID: blockID,
                x: Double(viewController.editorStyle.gutterWidth) * 0.5,
                yFraction: 0.5,
                viewController: viewController
            )
        else {
            return nil
        }
        return viewController.session.hitTest(
            documentPoint: point,
            region: region,
            viewport: viewController.currentViewport()
        )
    }

    private static func blockPoint(
        blockID: BlockID,
        x: Double,
        yFraction: Double,
        viewController: UIBenchmarkHost
    ) -> EditorPoint? {
        guard
            let frame = viewController.session.blockRevealFrame(
                for: blockID,
                viewport: viewController.currentViewport()
            )
        else { return nil }
        return EditorPoint(
            x: x,
            y: frame.y + frame.height * min(max(yFraction, 0), 1)
        )
    }

    private static func centerBlock(_ blockID: BlockID, viewController: UIBenchmarkHost) {
        guard
            let frame = viewController.session.blockRevealFrame(
                for: blockID,
                viewport: viewController.currentViewport()
            )
        else { return }
        let visibleHeight = Double(viewController.scrollView.contentView.bounds.height)
        let targetY = max(0, frame.y - visibleHeight * 0.45)
        setScrollY(targetY, viewController: viewController)
        viewController.renderAndSyncSurface(makeFirstResponder: false)
        viewController.scrollView.documentView?.displayIfNeeded()
    }

    private static func targetBlockID(blockCount: Int) -> BlockID {
        UIBenchmarkFixture.blockID(targetBlockIndex(blockCount: blockCount))
    }

    private static func secondaryBlockID(blockCount: Int) -> BlockID {
        UIBenchmarkFixture.blockID(secondaryBlockIndex(blockCount: blockCount))
    }

    private static func subtreeRootBlockID(blockCount: Int, subtreeNodeCount: Int?) -> BlockID {
        UIBenchmarkFixture.blockID(
            UIBenchmarkFixture.subtreeRootIndex(
                blockCount: blockCount,
                subtreeNodeCount: subtreeNodeCount
            )
        )
    }

    private static func subtreeLastBlockID(blockCount: Int, subtreeNodeCount: Int?) -> BlockID {
        UIBenchmarkFixture.blockID(
            UIBenchmarkFixture.subtreeLastIndex(
                blockCount: blockCount,
                subtreeNodeCount: subtreeNodeCount
            )
        )
    }

    private static func subtreeBeforeTargetBlockID(
        blockCount: Int,
        subtreeNodeCount: Int?
    ) -> BlockID {
        UIBenchmarkFixture.blockID(
            UIBenchmarkFixture.subtreeBeforeTargetIndex(
                blockCount: blockCount,
                subtreeNodeCount: subtreeNodeCount
            )
        )
    }

    private static func subtreeAfterTargetBlockID(
        blockCount: Int,
        subtreeNodeCount: Int?
    ) -> BlockID {
        UIBenchmarkFixture.blockID(
            UIBenchmarkFixture.subtreeAfterTargetIndex(
                blockCount: blockCount,
                subtreeNodeCount: subtreeNodeCount
            )
        )
    }

    private static func targetBlockIndex(blockCount: Int) -> Int {
        max(1, min(blockCount - 2, blockCount / 2))
    }

    private static func secondaryBlockIndex(blockCount: Int) -> Int {
        max(1, min(blockCount - 1, targetBlockIndex(blockCount: blockCount) + 8))
    }

    private static func setScrollY(_ y: Double, viewController: UIBenchmarkHost) {
        viewController.scrollDocument(to: y)
    }

    private static func write(_ contents: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
