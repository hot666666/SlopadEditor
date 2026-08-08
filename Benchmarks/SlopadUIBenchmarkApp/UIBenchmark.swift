import AppKit
import Darwin
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
    var preparedEntryLimit: Int
    var preparedEstimatedCostLimit: Int

    var preparedLayoutRunRole: String {
        preparedEntryLimit == 1
            ? "same-head-entry-limit-1-control"
            : "bounded-store-candidate"
    }
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
    case repeatedViewport = "repeated-viewport"
    case forwardReverseScroll = "forward-reverse-scroll"
    case widthResize = "width-resize"
    case pressureRecovery = "pressure-recovery"
    case longActiveParagraph = "long-active-paragraph"
    case coldFirstLayout = "cold-first-layout"
    case textSelectionDrag = "text-selection-drag"

    init(argument: String) {
        self = UIBenchmarkScenario(rawValue: argument) ?? .scroll
    }

    var usesSubtreeFixture: Bool {
        switch self {
        case .subtreeDelete, .subtreeReorder:
            return true
        case .scroll, .nativeInsert, .composition, .heightExpansion, .blockSelection,
            .blockReorder, .styleChange, .unicodeNavigation, .repeatedViewport,
            .forwardReverseScroll, .widthResize, .pressureRecovery, .longActiveParagraph,
            .coldFirstLayout, .textSelectionDrag, .mixed:
            return false
        }
    }

    var requiresFreshDocumentPerFrame: Bool {
        switch self {
        case .subtreeDelete, .coldFirstLayout:
            return true
        case .scroll, .nativeInsert, .composition, .heightExpansion, .blockSelection,
            .blockReorder, .subtreeReorder, .styleChange, .unicodeNavigation,
            .repeatedViewport, .forwardReverseScroll, .widthResize, .pressureRecovery,
            .longActiveParagraph, .textSelectionDrag, .mixed:
            return false
        }
    }
}

private enum UIBenchmarkValidationError: Error {
    case widthResizeDidNotReachWindowWidth(expected: Double, actual: Double)
    case requestWidthDoesNotMatchViewport(viewport: Double, request: Double)
    case viewportWidthDidNotResize(Double)
    case textSelectionDragGeometryUnavailable(BlockID)
    case textSelectionDragDidNotProduceTextSelection
    case forwardReverseScrollExceededLocalSpan(actual: Double, limit: Double)
    case forwardReverseScrollStepTooLarge(actual: Double, limit: Double)
    case forwardReverseScrollHadNoReversePathHits
    case sameHeadControlDidNotCaptureDisplayPrepare
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
        let resolvedActiveTextLength =
            activeTextLength ?? (scenario == .longActiveParagraph ? 16_384 : nil)
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
                        text: scenario == .unicodeNavigation || scenario == .longActiveParagraph
                            ? unicodeNavigationText(
                                for: index,
                                length: index == targetIndex ? resolvedActiveTextLength : nil
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

    func handlePreparedLayoutMemoryPressure(_ pressure: TextKitPreparedLayoutMemoryPressure) {
        editorViewController.handlePreparedLayoutMemoryPressure(pressure)
    }

    func handleMouseDown(documentPoint: EditorPoint) {
        editorViewController.handleMouseDown(
            documentPoint: CGPoint(x: CGFloat(documentPoint.x), y: CGFloat(documentPoint.y)),
            clickCount: 1
        )
    }

    func handleMouseDragged(documentPoint: EditorPoint) {
        editorViewController.handleMouseDragged(
            documentPoint: CGPoint(x: CGFloat(documentPoint.x), y: CGFloat(documentPoint.y))
        )
    }

    func handleMouseUp(documentPoint: EditorPoint) {
        editorViewController.handleMouseUp(
            documentPoint: CGPoint(x: CGFloat(documentPoint.x), y: CGFloat(documentPoint.y))
        )
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
    private let preparedEntryLimit: Int
    private let preparedEstimatedCostLimit: Int
    private let preparedLayoutRunRole: String
    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        private var instrumentationAtFrameStart =
            TextKitPreparedLayoutInstrumentationSnapshot.zero
        private var instrumentationAtDisplayStart =
            TextKitPreparedLayoutInstrumentationSnapshot.zero
    #endif

    init(
        preparedEntryLimit: Int,
        preparedEstimatedCostLimit: Int,
        preparedLayoutRunRole: String
    ) {
        self.preparedEntryLimit = preparedEntryLimit
        self.preparedEstimatedCostLimit = preparedEstimatedCostLimit
        self.preparedLayoutRunRole = preparedLayoutRunRole
    }

    func beginFrame(index: Int, scrollY: Double) {
        currentSample = UIBenchmarkFrameSample(frame: index, scrollY: scrollY)
        currentSample?.preparedLayoutEntryLimit = preparedEntryLimit
        currentSample?.preparedLayoutEstimatedCostLimit = preparedEstimatedCostLimit
        currentSample?.preparedLayoutRunRole = preparedLayoutRunRole
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            instrumentationAtFrameStart = TextKitBlockTextLayouter.preparedLayoutInstrumentation
            instrumentationAtDisplayStart = instrumentationAtFrameStart
        #endif
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

    func beginDisplay() {
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            instrumentationAtDisplayStart =
                TextKitBlockTextLayouter.preparedLayoutInstrumentation
        #endif
    }

    func recordWidths(
        windowContentWidth: Double,
        viewportWidth: Double,
        requestAvailableWidth: Double
    ) {
        currentSample?.windowContentWidth = windowContentWidth
        currentSample?.viewportWidth = viewportWidth
        currentSample?.requestAvailableWidth = requestAvailableWidth
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

    func finishFrame(totalNanoseconds: UInt64, processPhysicalFootprintBytes: UInt64) {
        currentSample?.frameNanoseconds = totalNanoseconds
        currentSample?.processPhysicalFootprintBytes = processPhysicalFootprintBytes
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            recordPreparedLayoutInstrumentation(
                TextKitBlockTextLayouter.preparedLayoutInstrumentation
            )
        #endif
        if let currentSample {
            samples.append(currentSample)
        }
        currentSample = nil
    }

    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        private func recordPreparedLayoutInstrumentation(
            _ end: TextKitPreparedLayoutInstrumentationSnapshot
        ) {
            let start = instrumentationAtFrameStart
            currentSample?.preparedLayoutLookupCount = max(0, end.lookups - start.lookups)
            currentSample?.preparedLayoutHitCount = max(0, end.hits - start.hits)
            currentSample?.prepareLayoutCount = max(0, end.prepares - start.prepares)
            currentSample?.displayPrepareLayoutCount = max(
                0,
                end.prepares - instrumentationAtDisplayStart.prepares
            )
            currentSample?.attributedStringBuildCount = max(
                0,
                end.attributedStringBuilds - start.attributedStringBuilds
            )
            currentSample?.preparedLayoutCapacityEvictionCount = max(
                0,
                end.capacityEvictions - start.capacityEvictions
            )
            currentSample?.preparedLayoutCapacityRejectionCount = max(
                0,
                end.capacityRejections - start.capacityRejections
            )
            currentSample?.preparedLayoutPressureEvictionCount = max(
                0,
                end.pressureEvictions - start.pressureEvictions
            )
            currentSample?.preparedLayoutInvalidationRemovalCount = max(
                0,
                end.invalidationRemovals - start.invalidationRemovals
            )
            currentSample?.preparedLayoutOversizedPinnedInsertionCount = max(
                0,
                end.oversizedPinnedInsertions - start.oversizedPinnedInsertions
            )
            currentSample?.preparedLayoutResidentEntryCount = end.residentEntryCount
            currentSample?.preparedLayoutResidentEstimatedCost = end.residentEstimatedCost
            currentSample?.preparedLayoutResidentEntryHighWater = end.residentEntryHighWater
            currentSample?.preparedLayoutResidentEstimatedCostHighWater =
                end.residentEstimatedCostHighWater
            currentSample?.preparedLayoutPinnedEntryCount = end.pinnedEntryCount
            currentSample?.preparedLayoutOverBudgetContextCount =
                end.overEstimatedCostLimitContextCount
        }
    #endif

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
        "prepareLayoutCount",
        "displayPrepareLayoutCount",
        "attributedStringBuildCount",
        "heightIndexRebuildCount",
        "heightIndexInsertCount",
        "heightIndexRemoveCount",
        "heightIndexMoveCount",
        "heightIndexUpdateHeightCount",
        "preparedLayoutLookupCount",
        "preparedLayoutHitCount",
        "preparedLayoutCapacityEvictionCount",
        "preparedLayoutCapacityRejectionCount",
        "preparedLayoutPressureEvictionCount",
        "preparedLayoutInvalidationRemovalCount",
        "preparedLayoutOversizedPinnedInsertionCount",
        "preparedLayoutResidentEntryCount",
        "preparedLayoutResidentEstimatedCost",
        "preparedLayoutResidentEntryHighWater",
        "preparedLayoutResidentEstimatedCostHighWater",
        "preparedLayoutPinnedEntryCount",
        "preparedLayoutOverBudgetContextCount",
        "processPhysicalFootprintBytes",
        "preparedLayoutRunRole",
        "preparedLayoutEntryLimit",
        "preparedLayoutEstimatedCostLimit",
        "windowContentWidth",
        "viewportWidth",
        "requestAvailableWidth",
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
    var prepareLayoutCount: Int = 0
    var displayPrepareLayoutCount: Int = 0
    var attributedStringBuildCount: Int = 0
    var heightIndexRebuildCount: Int = 0
    var heightIndexInsertCount: Int = 0
    var heightIndexRemoveCount: Int = 0
    var heightIndexMoveCount: Int = 0
    var heightIndexUpdateHeightCount: Int = 0
    var preparedLayoutLookupCount: Int = 0
    var preparedLayoutHitCount: Int = 0
    var preparedLayoutCapacityEvictionCount: Int = 0
    var preparedLayoutCapacityRejectionCount: Int = 0
    var preparedLayoutPressureEvictionCount: Int = 0
    var preparedLayoutInvalidationRemovalCount: Int = 0
    var preparedLayoutOversizedPinnedInsertionCount: Int = 0
    var preparedLayoutResidentEntryCount: Int = 0
    var preparedLayoutResidentEstimatedCost: Int = 0
    var preparedLayoutResidentEntryHighWater: Int = 0
    var preparedLayoutResidentEstimatedCostHighWater: Int = 0
    var preparedLayoutPinnedEntryCount: Int = 0
    var preparedLayoutOverBudgetContextCount: Int = 0
    var processPhysicalFootprintBytes: UInt64 = 0
    var preparedLayoutRunRole: String = "unavailable"
    var preparedLayoutEntryLimit: Int = 0
    var preparedLayoutEstimatedCostLimit: Int = 0
    var windowContentWidth: Double = 0
    var viewportWidth: Double = 0
    var requestAvailableWidth: Double = 0

    var frameMilliseconds: Double {
        milliseconds(frameNanoseconds)
    }

    var operationMilliseconds: Double {
        milliseconds(operationNanoseconds)
    }

    func csvRow(blockCount: Int, scenario: String) -> String {
        // Split so the type checker does not have to solve one oversized literal.
        let head: [String] = [
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
        ]
        let rest: [String] = [
            String(visibleOrderEntryCount),
            String(visibleRenderedBlockCount),
            String(layoutInputBlockCount),
            String(layoutOutputBlockCount),
            String(cacheHitCount),
            String(cacheMissCount),
            String(prepareLayoutCount),
            String(displayPrepareLayoutCount),
            String(attributedStringBuildCount),
            String(heightIndexRebuildCount),
            String(heightIndexInsertCount),
            String(heightIndexRemoveCount),
            String(heightIndexMoveCount),
            String(heightIndexUpdateHeightCount),
            String(preparedLayoutLookupCount),
            String(preparedLayoutHitCount),
            String(preparedLayoutCapacityEvictionCount),
            String(preparedLayoutCapacityRejectionCount),
            String(preparedLayoutPressureEvictionCount),
            String(preparedLayoutInvalidationRemovalCount),
            String(preparedLayoutOversizedPinnedInsertionCount),
            String(preparedLayoutResidentEntryCount),
            String(preparedLayoutResidentEstimatedCost),
            String(preparedLayoutResidentEntryHighWater),
            String(preparedLayoutResidentEstimatedCostHighWater),
            String(preparedLayoutPinnedEntryCount),
            String(preparedLayoutOverBudgetContextCount),
            String(processPhysicalFootprintBytes),
            preparedLayoutRunRole,
            String(preparedLayoutEntryLimit),
            String(preparedLayoutEstimatedCostLimit),
            format(windowContentWidth),
            format(viewportWidth),
            format(requestAvailableWidth),
        ]
        return (head + rest).map(csvEscape).joined(separator: ",")
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

private func processPhysicalFootprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(
                mach_task_self_,
                task_flavor_t(TASK_VM_INFO),
                rebound,
                &count
            )
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

@MainActor
enum UIBenchmarkRunner {
    static func run(
        window: NSWindow,
        viewController: UIBenchmarkHost,
        options: UIBenchmarkOptions
    ) throws {
        let recorder = UIBenchmarkRecorder(
            preparedEntryLimit: options.preparedEntryLimit,
            preparedEstimatedCostLimit: options.preparedEstimatedCostLimit,
            preparedLayoutRunRole: options.preparedLayoutRunRole
        )
        viewController.uiBenchmarkRecorder = recorder
        defer { viewController.uiBenchmarkRecorder = nil }

        let scenario = UIBenchmarkScenario(argument: options.scenario)
        if scenario != .coldFirstLayout {
            viewController.renderAndSyncSurface(makeFirstResponder: false)
            viewController.scrollView.documentView?.displayIfNeeded()
            window.displayIfNeeded()
            if !scenario.requiresFreshDocumentPerFrame {
                prepare(scenario: scenario, options: options, viewController: viewController)
            }
        }

        let frameCount = max(1, options.frameCount)
        var previousForwardReverseScrollY =
            Double(viewController.scrollView.contentView.bounds.origin.y)
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
            if scenario == .forwardReverseScroll {
                try validateForwardReverseScrollPosition(
                    scrollY,
                    previousScrollY: previousForwardReverseScrollY,
                    viewController: viewController
                )
                previousForwardReverseScrollY = scrollY
            }
            setScrollY(scrollY, viewController: viewController)

            recorder.beginFrame(index: frame, scrollY: scrollY)
            let frameStart = DispatchTime.now().uptimeNanoseconds

            let operationStart = DispatchTime.now().uptimeNanoseconds
            let operation = try performOperation(
                scenario: scenario,
                frame: frame,
                options: options,
                window: window,
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
            let viewportWidth = viewController.currentViewport().width
            let requestAvailableWidth =
                viewController.snapshot?.visibleBlocks.first?.textRender.measureRequest
                .availableWidth ?? 0
            recorder.recordWidths(
                windowContentWidth: Double(window.contentLayoutRect.width),
                viewportWidth: viewportWidth,
                requestAvailableWidth: requestAvailableWidth
            )
            if scenario == .widthResize {
                try validateWidthResize(
                    frame: frame,
                    windowContentWidth: Double(window.contentLayoutRect.width),
                    viewportWidth: viewportWidth,
                    requestAvailableWidth: requestAvailableWidth
                )
            }
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

            recorder.beginDisplay()
            let displayStart = DispatchTime.now().uptimeNanoseconds
            viewController.scrollView.documentView?.displayIfNeeded()
            window.displayIfNeeded()
            recorder.recordDisplay(
                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - displayStart)

            recorder.finishFrame(
                totalNanoseconds: DispatchTime.now().uptimeNanoseconds - frameStart,
                processPhysicalFootprintBytes: processPhysicalFootprintBytes()
            )
        }

        try validateCompletedRun(
            scenario: scenario,
            options: options,
            samples: recorder.samples
        )

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
        switch scenario {
        case .scroll, .repeatedViewport, .forwardReverseScroll, .widthResize,
            .pressureRecovery, .coldFirstLayout:
            return
        case .nativeInsert, .composition, .heightExpansion, .blockSelection, .blockReorder,
            .subtreeDelete, .subtreeReorder, .styleChange, .unicodeNavigation,
            .longActiveParagraph, .textSelectionDrag, .mixed:
            break
        }
        let target = targetBlockID(blockCount: options.blockCount)
        centerBlock(target, viewController: viewController)

        switch scenario {
        case .nativeInsert, .composition, .heightExpansion, .unicodeNavigation,
            .longActiveParagraph, .mixed:
            let targetIndex = targetBlockIndex(blockCount: options.blockCount)
            viewController.focus(
                blockID: target,
                offset: scenario == .unicodeNavigation || scenario == .longActiveParagraph
                    ? UIBenchmarkFixture.unicodeNavigationText(
                        for: targetIndex,
                        length: options.activeTextLength
                            ?? (scenario == .longActiveParagraph ? 16_384 : nil)
                    ).count
                    : UIBenchmarkFixture.text(for: targetIndex).count
            )
            viewController.renderAndSyncSurface(makeFirstResponder: true)

        case .blockSelection, .blockReorder, .subtreeDelete, .subtreeReorder, .styleChange,
            .textSelectionDrag:
            viewController.renderAndSyncSurface(makeFirstResponder: false)

        case .scroll, .repeatedViewport, .forwardReverseScroll, .widthResize,
            .pressureRecovery, .coldFirstLayout:
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
        case .scroll, .mixed, .forwardReverseScroll:
            break
        case .nativeInsert, .composition, .heightExpansion, .blockSelection, .blockReorder,
            .subtreeDelete, .subtreeReorder, .styleChange, .unicodeNavigation,
            .repeatedViewport, .widthResize, .pressureRecovery, .longActiveParagraph,
            .coldFirstLayout, .textSelectionDrag:
            return Double(viewController.scrollView.contentView.bounds.origin.y)
        }

        guard viewController.scrollView.documentView != nil else { return 0 }
        let visibleHeight = viewController.scrollView.contentView.bounds.height
        let documentHeight = viewController.scrollView.documentView?.frame.height ?? visibleHeight
        let maxY = max(0, documentHeight - visibleHeight)
        guard maxY > 0, frameCount > 1 else { return 0 }

        let progress = Double(frame) / Double(frameCount - 1)
        if scenario == .forwardReverseScroll {
            let targetSpan = min(maxY, visibleHeight * 4)
            let phase = frame % 16
            let step = phase < 8 ? phase + 1 : 15 - phase
            return Double(targetSpan) * Double(step) / 8
        }
        return Double(maxY) * progress
    }

    private static func performOperation(
        scenario: UIBenchmarkScenario,
        frame: Int,
        options: UIBenchmarkOptions,
        window: NSWindow,
        viewController: UIBenchmarkHost
    ) throws -> String {
        switch scenario {
        case .scroll:
            return "scroll"

        case .repeatedViewport:
            return "repeatedViewport"

        case .forwardReverseScroll:
            return frame % 16 < 8 ? "forwardScroll" : "reverseScroll"

        case .widthResize:
            let width: CGFloat = frame.isMultiple(of: 2) ? 920 : 680
            window.setContentSize(NSSize(width: width, height: 680))
            SlopadUIBenchmarkApp.layoutBenchmarkWindow(window, host: viewController)
            return "widthResize"

        case .pressureRecovery:
            viewController.handlePreparedLayoutMemoryPressure(
                frame.isMultiple(of: 2) ? .warning : .critical
            )
            return frame.isMultiple(of: 2) ? "warningPressure" : "criticalPressure"

        case .longActiveParagraph:
            insertText(frame: frame, options: options, viewController: viewController)
            return "longActiveInsertText"

        case .coldFirstLayout:
            return "coldFirstLayout"

        case .textSelectionDrag:
            try dragTextSelection(frame: frame, options: options, viewController: viewController)
            return "textSelectionDrag"

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
                    .command(.navigate(.moveWordLeft(viewport: viewport)))
                )
                return "moveWordLeft"
            }
            _ = viewController.handleNativeInputEvent(
                .command(.navigate(.moveWordRight(viewport: viewport)))
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

    private static func dragTextSelection(
        frame: Int,
        options: UIBenchmarkOptions,
        viewController: UIBenchmarkHost
    ) throws {
        let blockID = targetBlockID(blockCount: options.blockCount)
        let textOriginX =
            viewController.editorStyle.gutterWidth
            + viewController.editorStyle.contentHorizontalPadding
        let startsForward = frame.isMultiple(of: 2)
        guard
            let leadingPoint = blockPoint(
                blockID: blockID,
                x: textOriginX + 8,
                yFraction: 0.5,
                viewController: viewController
            ),
            let trailingPoint = blockPoint(
                blockID: blockID,
                x: textOriginX + 220,
                yFraction: 0.5,
                viewController: viewController
            )
        else {
            throw UIBenchmarkValidationError.textSelectionDragGeometryUnavailable(blockID)
        }

        let start = startsForward ? leadingPoint : trailingPoint
        let end = startsForward ? trailingPoint : leadingPoint
        viewController.handleMouseDown(documentPoint: start)
        for step in 1...4 {
            let progress = Double(step) / 4
            viewController.handleMouseDragged(
                documentPoint: EditorPoint(
                    x: start.x + (end.x - start.x) * progress,
                    y: start.y + (end.y - start.y) * progress
                )
            )
        }
        viewController.handleMouseUp(documentPoint: end)
        guard case .text = viewController.snapshot?.selection else {
            throw UIBenchmarkValidationError.textSelectionDragDidNotProduceTextSelection
        }
    }

    private static func validateForwardReverseScrollPosition(
        _ scrollY: Double,
        previousScrollY: Double,
        viewController: UIBenchmarkHost
    ) throws {
        let viewportHeight = Double(viewController.scrollView.contentView.bounds.height)
        let documentHeight = Double(
            viewController.scrollView.documentView?.frame.height
                ?? viewController.scrollView.contentView.bounds.height
        )
        let maxY = max(0, documentHeight - viewportHeight)
        let localSpan = min(maxY, viewportHeight * 4)
        let epsilon = 0.5
        guard scrollY >= -epsilon, scrollY <= localSpan + epsilon else {
            throw UIBenchmarkValidationError.forwardReverseScrollExceededLocalSpan(
                actual: scrollY,
                limit: localSpan
            )
        }
        let delta = abs(scrollY - previousScrollY)
        let maximumDelta = viewportHeight * 0.5
        guard delta <= maximumDelta + epsilon else {
            throw UIBenchmarkValidationError.forwardReverseScrollStepTooLarge(
                actual: delta,
                limit: maximumDelta
            )
        }
    }

    private static func validateCompletedRun(
        scenario: UIBenchmarkScenario,
        options: UIBenchmarkOptions,
        samples: [UIBenchmarkFrameSample]
    ) throws {
        #if SLOPAD_BENCHMARK_INSTRUMENTATION
            if scenario == .forwardReverseScroll {
                let reverseHitCount = samples
                    .filter { $0.operation == "reverseScroll" }
                    .reduce(0) { $0 + $1.preparedLayoutHitCount }
                guard reverseHitCount > 0 else {
                    throw UIBenchmarkValidationError.forwardReverseScrollHadNoReversePathHits
                }
            }
            if scenario == .coldFirstLayout, options.preparedEntryLimit == 1 {
                guard samples.contains(where: {
                    $0.displayPrepareLayoutCount > 0
                        && $0.prepareLayoutCount >= $0.displayPrepareLayoutCount
                }) else {
                    throw UIBenchmarkValidationError.sameHeadControlDidNotCaptureDisplayPrepare
                }
            }
        #endif
    }

    private static func validateWidthResize(
        frame: Int,
        windowContentWidth: Double,
        viewportWidth: Double,
        requestAvailableWidth: Double
    ) throws {
        let expectedWindowWidth = frame.isMultiple(of: 2) ? 920.0 : 680.0
        guard abs(windowContentWidth - expectedWindowWidth) < 1 else {
            throw UIBenchmarkValidationError.widthResizeDidNotReachWindowWidth(
                expected: expectedWindowWidth,
                actual: windowContentWidth
            )
        }
        guard abs(viewportWidth - requestAvailableWidth) < 1 else {
            throw UIBenchmarkValidationError.requestWidthDoesNotMatchViewport(
                viewport: viewportWidth,
                request: requestAvailableWidth
            )
        }
        let isExpectedViewportBand = frame.isMultiple(of: 2)
            ? viewportWidth > 800
            : viewportWidth < 800
        guard isExpectedViewportBand else {
            throw UIBenchmarkValidationError.viewportWidthDidNotResize(viewportWidth)
        }
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
