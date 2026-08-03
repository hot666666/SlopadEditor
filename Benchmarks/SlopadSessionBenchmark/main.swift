#if SLOPAD_BENCHMARK_INSTRUMENTATION

import Dispatch
import Foundation
import SlopadEngine

typealias EngineTextRange = SlopadEngine.TextRange

// MARK: - CLI

struct BenchmarkOptions {
    var blockCounts: [Int] = [100, 1_000, 10_000]
    var iterations: Int = 5
    var outputPath: String?
    var gitRevision: String =
        ProcessInfo.processInfo.environment["SLOPAD_BENCHMARK_GIT_REVISION"] ?? "unknown"

    init(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--block-counts":
                if index + 1 < arguments.count {
                    blockCounts = arguments[index + 1]
                        .split(separator: ",")
                        .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    index += 2
                } else {
                    index += 1
                }

            case "--iterations":
                if index + 1 < arguments.count {
                    iterations = max(1, Int(arguments[index + 1]) ?? iterations)
                    index += 2
                } else {
                    index += 1
                }

            case "--output":
                if index + 1 < arguments.count {
                    outputPath = arguments[index + 1]
                    index += 2
                } else {
                    index += 1
                }

            case "--git-revision":
                if index + 1 < arguments.count {
                    gitRevision = arguments[index + 1]
                    index += 2
                } else {
                    index += 1
                }

            default:
                index += 1
            }
        }

        blockCounts = blockCounts.filter { $0 > 1 }.sorted()
        if blockCounts.isEmpty {
            blockCounts = [100, 1_000, 10_000]
        }
    }
}

// MARK: - Timing

func measureNanoseconds(_ body: () -> Void) -> UInt64 {
    let start = DispatchTime.now().uptimeNanoseconds
    body()
    return DispatchTime.now().uptimeNanoseconds - start
}

// MARK: - Benchmark Layouter

final class BenchmarkTextLayouter: BlockTextLayoutProtocol, @unchecked Sendable {
    private let lineHeight = 20.0
    private let verticalPadding = 8.0
    private let characterWidth = 7.5

    func measure(_ request: BlockMeasureRequest) -> BlockMeasurement {
        let lineCount = wrappedLineCount(for: request)
        let kindMultiplier = heightMultiplier(for: request.kind)
        let depthPadding = Double(request.depth) * 2.0
        return BlockMeasurement(
            height: Double(lineCount) * lineHeight * kindMultiplier + verticalPadding + depthPadding,
            firstBaseline: lineHeight * 0.8
        )
    }

    func textFrame(for request: BlockMeasureRequest, measuredHeight: Double?) -> EditorRect {
        let depthInset = Double(request.depth) * 18.0
        return EditorRect(
            x: depthInset,
            y: 4,
            width: max(1, request.availableWidth - depthInset),
            height: max(1, (measuredHeight ?? lineHeight) - 8)
        )
    }

    func lineFragments(for request: BlockMeasureRequest) -> [LineFragmentSnapshot] {
        let lines = splitWrappedLines(request)
        var fragments: [LineFragmentSnapshot] = []
        fragments.reserveCapacity(lines.count)
        var y = 0.0
        for line in lines {
            fragments.append(
                LineFragmentSnapshot(
                    blockID: request.blockID,
                    range: line.range,
                    rect: EditorRect(
                        x: 0,
                        y: y,
                        width: max(1, Double(max(1, line.range.length)) * characterWidth),
                        height: lineHeight
                    )
                )
            )
            y += lineHeight
        }
        return fragments
    }

    func caretRect(for position: TextPosition, in request: BlockMeasureRequest) -> EditorRect? {
        let offset = EngineTextRange.point(position.offset)
            .clamped(to: request.text.count)
            .lowerBound
        guard let line = splitWrappedLines(request).reversed().first(where: {
            $0.range.lowerBound <= offset && offset <= $0.range.upperBound
        }) else {
            return nil
        }
        let y = Double(line.index) * lineHeight
        return EditorRect(
            x: Double(offset - line.range.lowerBound) * characterWidth,
            y: y,
            width: 1,
            height: lineHeight
        )
    }

    func selectionRects(for range: EngineTextRange, in request: BlockMeasureRequest) -> [EditorRect] {
        let clamped = range.clamped(to: request.text.count)
        guard !clamped.isEmpty else { return [] }
        return splitWrappedLines(request).compactMap { line in
            guard line.range.intersects(clamped) else { return nil }
            let lower = max(line.range.lowerBound, clamped.lowerBound)
            let upper = min(line.range.upperBound, clamped.upperBound)
            return EditorRect(
                x: Double(lower - line.range.lowerBound) * characterWidth,
                y: Double(line.index) * lineHeight,
                width: max(1, Double(upper - lower) * characterWidth),
                height: lineHeight
            )
        }
    }

    func textPosition(at point: EditorPoint, in request: BlockMeasureRequest) -> TextPosition {
        let lines = splitWrappedLines(request)
        let lineIndex = min(max(0, Int((point.y / lineHeight).rounded(.down))), lines.count - 1)
        let line = lines[lineIndex]
        let offsetInLine = Int((max(0, point.x) / characterWidth).rounded())
        return TextPosition(
            blockID: request.blockID,
            offset: min(line.range.upperBound, line.range.lowerBound + offsetInLine)
        )
    }

    private func wrappedLineCount(for request: BlockMeasureRequest) -> Int {
        splitWrappedLines(request).count
    }

    private func splitWrappedLines(_ request: BlockMeasureRequest) -> [WrappedLine] {
        let charsPerLine = max(8, Int((request.availableWidth - Double(request.depth) * 18) / characterWidth))
        var lines: [WrappedLine] = []
        var lower = 0
        var lineIndex = 0

        for rawLine in request.text.split(separator: "\n", omittingEmptySubsequences: false) {
            let length = rawLine.count
            if length == 0 {
                lines.append(WrappedLine(index: lineIndex, range: EngineTextRange(lower, lower)))
                lineIndex += 1
            } else {
                var consumed = 0
                while consumed < length {
                    let count = min(charsPerLine, length - consumed)
                    lines.append(
                        WrappedLine(
                            index: lineIndex,
                            range: EngineTextRange(lower + consumed, lower + consumed + count)
                        )
                    )
                    consumed += count
                    lineIndex += 1
                }
            }
            lower += length + 1
        }

        if lines.isEmpty {
            lines.append(WrappedLine(index: 0, range: EngineTextRange.point(0)))
        }
        return lines
    }

    private func heightMultiplier(for kind: BlockKind) -> Double {
        switch kind {
        case .heading(let level):
            switch level {
            case .h1:
                return 1.55
            case .h2:
                return 1.35
            case .h3:
                return 1.18
            }
        case .divider:
            return 0.5
        case .codeBlock:
            return 1.12
        default:
            return 1.0
        }
    }
}

struct WrappedLine {
    var index: Int
    var range: EngineTextRange
}

// MARK: - Scenarios

enum BenchmarkAction: String, CaseIterable {
    case initialRender
    case warmScrollRender
    case singleBlockInsert
    case compositionUpdate
    case enterSplit
    case backspaceMerge
    case blockDelete
    case blockReorder
    case subtreeDelete
    case subtreeReorder
    case structuralIndent
    case structuralOutdent
    case heightExpansionHitTest
    case widthChange
    // Historical CSV identifier; this now measures atomic text-layout backend replacement.
    case styleRevisionChange
}

struct Scenario {
    var session: EditorSession
    var layouter: BenchmarkTextLayouter
    var viewport: EditorViewport
    var alternateViewport: EditorViewport
    var targetID: BlockID
    var secondaryID: BlockID
    var targetIndex: Int
}

struct IterationResult {
    var handleDurationNs: UInt64
    var damageDurationNs: UInt64
    var renderDurationNs: UInt64
    var documentBlockCountAfter: Int
    var totalHeight: Double
    var sessionMetrics: EditorSessionBenchmarkMetrics
    var visibleRenderedBlockCount: Int
    var damageRectCount: Int
    var damageArea: Double
    var invalidationBlockCount: Int
    var visibleSequenceChanged: Bool
    var layoutGeometryChanged: Bool
    var layoutDirtyAfterHandle: Bool
}

func runIteration(action: BenchmarkAction, blockCount: Int) -> IterationResult {
    let scenario = makeScenario(action: action, blockCount: blockCount)
    var handleDuration: UInt64 = 0
    var update: EditorUpdate?

    switch action {
    case .initialRender:
        break

    case .warmScrollRender:
        _ = scenario.session.render(in: scenario.viewport)

    case .singleBlockInsert:
        _ = scenario.session.render(in: scenario.viewport)
        handleDuration = measureNanoseconds {
            update = scenario.session.handleInput(.command(.insertText("Z")))
        }

    case .compositionUpdate:
        _ = scenario.session.render(in: scenario.viewport)
        handleDuration = measureNanoseconds {
            update = scenario.session.handleInput(
                .beginComposition(
                    blockID: scenario.targetID,
                    replacementRange: EngineTextRange(3, 8),
                    text: "marked"
                )
            )
        }

    case .enterSplit:
        _ = scenario.session.render(in: scenario.viewport)
        handleDuration = measureNanoseconds {
            update = scenario.session.handleInput(.command(.enter))
        }

    case .backspaceMerge:
        _ = scenario.session.render(in: scenario.viewport)
        handleDuration = measureNanoseconds {
            update = scenario.session.handleInput(.command(.deleteBackward))
        }

    case .blockDelete:
        _ = scenario.session.render(in: scenario.viewport)
        handleDuration = measureNanoseconds {
            update = scenario.session.handleInput(.command(.deleteBackward))
        }

    case .blockReorder:
        _ = scenario.session.render(in: scenario.viewport)
        let startFrame = scenario.session.blockRevealFrame(
            for: scenario.targetID,
            viewport: scenario.viewport
        )
        let dropFrame = scenario.session.blockRevealFrame(
            for: scenario.secondaryID,
            viewport: scenario.viewport
        )
        handleDuration = measureNanoseconds {
            if let startFrame, let dropFrame {
                let startPoint = EditorPoint(
                    x: 0,
                    y: startFrame.y + startFrame.height / 2
                )
                let dropPoint = EditorPoint(
                    x: 0,
                    y: dropFrame.y + dropFrame.height - 1
                )
                _ = scenario.session.handleInput(
                    .pointer(.beginBlockDrag(documentPoint: startPoint, viewport: scenario.viewport))
                )
                update = scenario.session.handleInput(
                    .pointer(.endBlockDrag(documentPoint: dropPoint, viewport: scenario.viewport))
                )
            }
        }

    case .subtreeDelete:
        _ = scenario.session.render(in: scenario.viewport)
        handleDuration = measureNanoseconds {
            update = scenario.session.handleInput(.command(.deleteBackward))
        }

    case .subtreeReorder:
        _ = scenario.session.render(in: scenario.viewport)
        let startFrame = scenario.session.blockRevealFrame(
            for: scenario.targetID,
            viewport: scenario.viewport
        )
        let dropFrame = scenario.session.blockRevealFrame(
            for: scenario.secondaryID,
            viewport: scenario.viewport
        )
        handleDuration = measureNanoseconds {
            if let startFrame, let dropFrame {
                let startPoint = EditorPoint(
                    x: 0,
                    y: startFrame.y + startFrame.height / 2
                )
                let dropPoint = EditorPoint(
                    x: 0,
                    y: dropFrame.y + dropFrame.height - 1
                )
                _ = scenario.session.handleInput(
                    .pointer(.beginBlockDrag(documentPoint: startPoint, viewport: scenario.viewport))
                )
                update = scenario.session.handleInput(
                    .pointer(.endBlockDrag(documentPoint: dropPoint, viewport: scenario.viewport))
                )
            }
        }

    case .structuralIndent:
        _ = scenario.session.render(in: scenario.viewport)
        handleDuration = measureNanoseconds {
            update = scenario.session.handleInput(.command(.indent))
        }

    case .structuralOutdent:
        _ = scenario.session.render(in: scenario.viewport)
        handleDuration = measureNanoseconds {
            update = scenario.session.handleInput(.command(.outdent))
        }

    case .heightExpansionHitTest:
        _ = scenario.session.render(in: scenario.viewport)
        handleDuration = measureNanoseconds {
            update = scenario.session.handleInput(.command(.insertText(heightExpansionText())))
            _ = scenario.session.hitTest(
                documentPoint: EditorPoint(
                    x: 0,
                    y: scenario.viewport.scrollY + scenario.viewport.height * 0.75
                ),
                region: .body,
                viewport: scenario.viewport
            )
            _ = scenario.session.blockRevealFrame(
                for: scenario.secondaryID,
                viewport: scenario.viewport
            )
        }

    case .widthChange:
        _ = scenario.session.render(in: scenario.viewport)

    case .styleRevisionChange:
        _ = scenario.session.render(in: scenario.viewport)
        let replacementLayouter = BenchmarkTextLayouter()
        handleDuration = measureNanoseconds {
            update = scenario.session.replaceTextLayoutBackend(with: replacementLayouter)
        }
    }

    let renderViewport: EditorViewport
    switch action {
    case .warmScrollRender, .widthChange:
        renderViewport = scenario.alternateViewport
    default:
        renderViewport = scenario.viewport
    }

    scenario.session.resetBenchmarkMetrics()
    var damageMetrics: EditorSessionBenchmarkMetrics?
    var damageRects: [EditorRect] = []
    let damageDuration = measureNanoseconds {
        if let update {
            damageRects = scenario.session.redrawRects(for: update, in: renderViewport)
        }
    }
    if update != nil {
        damageMetrics = scenario.session.lastBenchmarkMetrics
    }

    scenario.session.resetBenchmarkMetrics()
    var snapshot: EditorSessionSnapshot!
    let renderDuration = measureNanoseconds {
        snapshot = scenario.session.render(in: renderViewport)
    }
    let renderMetrics = scenario.session.lastBenchmarkMetrics
    let sessionMetrics = damageMetrics ?? renderMetrics

    return IterationResult(
        handleDurationNs: handleDuration,
        damageDurationNs: damageDuration,
        renderDurationNs: renderDuration,
        documentBlockCountAfter: scenario.session.documentBlockCount,
        totalHeight: snapshot.totalHeight,
        sessionMetrics: sessionMetrics,
        visibleRenderedBlockCount: snapshot.visibleBlocks.count,
        damageRectCount: damageRects.count,
        damageArea: damageRects.reduce(0) { $0 + $1.width * $1.height },
        invalidationBlockCount: update?.benchmarkInvalidationBlockCount ?? 0,
        visibleSequenceChanged: update?.benchmarkVisibleSequenceChanged ?? false,
        layoutGeometryChanged: update?.benchmarkLayoutGeometryChanged ?? false,
        layoutDirtyAfterHandle: update?.benchmarkLayoutDirty ?? false
    )
}

func makeScenario(action: BenchmarkAction, blockCount: Int) -> Scenario {
    let targetIndex = targetIndex(for: action, blockCount: blockCount)
    let secondaryIndex = secondaryIndex(for: action, blockCount: blockCount)
    let targetID = blockID(targetIndex)
    let secondaryID = blockID(secondaryIndex)
    let blocks: [EditorBlockInput]
    let selection: EditorSelection?

    switch action {
    case .singleBlockInsert:
        blocks = makeFlatBlocks(blockCount: blockCount)
        selection = .caret(blockID: targetID, offset: text(for: targetIndex).count)

    case .compositionUpdate:
        blocks = makeFlatBlocks(blockCount: blockCount)
        selection = .caret(blockID: targetID, offset: 8)

    case .enterSplit:
        blocks = makeFlatBlocks(blockCount: blockCount)
        selection = .caret(blockID: targetID, offset: text(for: targetIndex).count / 2)

    case .backspaceMerge:
        blocks = makeFlatBlocks(blockCount: blockCount)
        selection = .caret(blockID: targetID, offset: 0)

    case .blockDelete, .blockReorder, .structuralIndent:
        blocks = makeFlatBlocks(blockCount: blockCount)
        selection = .blocks(BlockSelection(blockIDs: [targetID]))

    case .subtreeDelete, .subtreeReorder:
        blocks = makeSubtreeBlocks(
            blockCount: blockCount,
            rootIndex: targetIndex,
            subtreeNodeCount: subtreeNodeCount(for: blockCount)
        )
        selection = .blocks(BlockSelection(blockIDs: [targetID]))

    case .structuralOutdent:
        blocks = makeOutdentBlocks(blockCount: blockCount, childIndex: targetIndex)
        selection = .blocks(BlockSelection(blockIDs: [targetID]))

    case .heightExpansionHitTest:
        blocks = makeFlatBlocks(blockCount: blockCount)
        selection = .caret(blockID: targetID, offset: text(for: targetIndex).count)

    case .initialRender, .warmScrollRender, .widthChange, .styleRevisionChange:
        blocks = makeFlatBlocks(blockCount: blockCount)
        selection = .caret(blockID: targetID, offset: 0)
    }

    let layouter = BenchmarkTextLayouter()
    let viewport = viewportAround(index: targetIndex, width: 720)
    let alternateViewport: EditorViewport
    switch action {
    case .widthChange:
        alternateViewport = EditorViewport(
            width: 940,
            scrollY: viewport.scrollY,
            height: viewport.height
        )
    default:
        alternateViewport = EditorViewport(
            width: viewport.width,
            scrollY: viewport.scrollY + viewport.height * 0.8,
            height: viewport.height
        )
    }

    return Scenario(
        session: EditorSession(blocks: blocks, selection: selection, textLayouter: layouter),
        layouter: layouter,
        viewport: viewport,
        alternateViewport: alternateViewport,
        targetID: targetID,
        secondaryID: secondaryID,
        targetIndex: targetIndex
    )
}

func makeFlatBlocks(blockCount: Int) -> [EditorBlockInput] {
    (0..<blockCount).map { blockInput(index: $0) }
}

func makeSubtreeBlocks(
    blockCount: Int,
    rootIndex: Int,
    subtreeNodeCount: Int
) -> [EditorBlockInput] {
    let subtreeRange = rootIndex..<min(blockCount, rootIndex + subtreeNodeCount)
    return (0..<blockCount).map { index in
        let parentID: BlockID?
        if index == rootIndex || !subtreeRange.contains(index) {
            parentID = nil
        } else if (index - rootIndex) % 4 == 1 {
            parentID = blockID(rootIndex)
        } else {
            parentID = blockID(index - 1)
        }
        return blockInput(index: index, parentID: parentID)
    }
}

func makeOutdentBlocks(blockCount: Int, childIndex: Int) -> [EditorBlockInput] {
    let parentIndex = max(0, childIndex - 1)
    let parentID = blockID(parentIndex)
    return (0..<blockCount).map { index in
        blockInput(index: index, parentID: index == childIndex ? parentID : nil)
    }
}

func blockInput(index: Int, parentID: BlockID? = nil) -> EditorBlockInput {
    EditorBlockInput(
        id: blockID(index),
        parentID: parentID,
        kind: kind(for: index),
        content: BlockContent(text: text(for: index))
    )
}

func blockID(_ index: Int) -> BlockID {
    BlockID("bench-\(index)")
}

func kind(for index: Int) -> BlockKind {
    if index % 97 == 0 {
        return .heading(level: .h2)
    }
    if index % 41 == 0 {
        return .todo(isChecked: index % 2 == 0)
    }
    if index % 29 == 0 {
        return .unorderedListItem
    }
    return .paragraph
}

func text(for index: Int) -> String {
    let base = "Block \(index) session layout benchmark text"
    switch index % 5 {
    case 0:
        return base + " with enough words to wrap at narrower widths and affect height."
    case 1:
        return base
    case 2:
        return base + "\nsecond visual line"
    case 3:
        return base + " short"
    default:
        return base + " with inline style sized content placeholder"
    }
}

func heightExpansionText() -> String {
    String(
        repeating: " expanded content that changes wrapping and downstream y positions",
        count: 40
    )
}

func targetIndex(for action: BenchmarkAction, blockCount: Int) -> Int {
    switch action {
    case .subtreeDelete, .subtreeReorder:
        return max(1, min(blockCount - 2, blockCount / 2 - subtreeNodeCount(for: blockCount) / 2))
    default:
        return max(1, min(blockCount - 2, blockCount / 2))
    }
}

func secondaryIndex(for action: BenchmarkAction, blockCount: Int) -> Int {
    let targetIndex = targetIndex(for: action, blockCount: blockCount)
    switch action {
    case .subtreeDelete, .subtreeReorder:
        return min(blockCount - 1, targetIndex + subtreeNodeCount(for: blockCount) + 12)
    default:
        return max(targetIndex + 1, min(blockCount - 1, targetIndex + 12))
    }
}

func subtreeNodeCount(for blockCount: Int) -> Int {
    min(max(6, blockCount / 20), 200)
}

func viewportAround(index: Int, width: Double) -> EditorViewport {
    let estimatedBlockHeight = 36.12
    let viewportHeight = 640.0
    return EditorViewport(
        width: width,
        scrollY: max(0, Double(index) * estimatedBlockHeight - viewportHeight / 2),
        height: viewportHeight
    )
}

// MARK: - Aggregation

struct BenchmarkSummary {
    var action: BenchmarkAction
    var blockCount: Int
    var targetIndex: Int
    var viewportWidth: Double
    var viewportHeight: Double
    var iterations: Int
    var documentBlockCountAfterMedian: Double
    var totalHeightMedian: Double
    var handleDurationMsMedian: Double
    var damageDurationMsMedian: Double
    var renderDurationMsMedian: Double
    var totalDurationMsMedian: Double
    var layoutFullRebuildCount: Int
    var layoutReusedSnapshotCount: Int
    var layoutIncrementalCount: Int
    var visibleOrderEntryCountMedian: Double
    var layoutInputBlockCountMedian: Double
    var layoutOutputBlockCountMedian: Double
    var visibleRenderedBlockCountMedian: Double
    var nonVisibleLayoutInputCountMedian: Double
    var cacheHitCountMedian: Double
    var cacheMissCountMedian: Double
    var heightIndexRebuildCountMedian: Double
    var heightIndexInsertCountMedian: Double
    var heightIndexRemoveCountMedian: Double
    var heightIndexMoveCountMedian: Double
    var heightIndexUpdateHeightCountMedian: Double
    var damageRectCountMedian: Double
    var damageAreaMedian: Double
    var invalidationBlockCountMedian: Double
    var visibleSequenceChangedCount: Int
    var layoutGeometryChangedCount: Int
    var layoutDirtyAfterHandleCount: Int
}

func summarize(
    action: BenchmarkAction,
    blockCount: Int,
    iterations: [IterationResult]
) -> BenchmarkSummary {
    let targetIndex = targetIndex(for: action, blockCount: blockCount)
    let viewport = viewportAround(index: targetIndex, width: 720)
    return BenchmarkSummary(
        action: action,
        blockCount: blockCount,
        targetIndex: targetIndex,
        viewportWidth: viewport.width,
        viewportHeight: viewport.height,
        iterations: iterations.count,
        documentBlockCountAfterMedian: median(iterations.map { Double($0.documentBlockCountAfter) }),
        totalHeightMedian: median(iterations.map(\.totalHeight)),
        handleDurationMsMedian: median(iterations.map { nanosecondsToMilliseconds($0.handleDurationNs) }),
        damageDurationMsMedian: median(iterations.map { nanosecondsToMilliseconds($0.damageDurationNs) }),
        renderDurationMsMedian: median(iterations.map { nanosecondsToMilliseconds($0.renderDurationNs) }),
        totalDurationMsMedian: median(
            iterations.map {
                nanosecondsToMilliseconds(
                    $0.handleDurationNs + $0.damageDurationNs + $0.renderDurationNs
                )
            }
        ),
        layoutFullRebuildCount: iterations.filter { $0.sessionMetrics.layoutMode == "fullRebuild" }.count,
        layoutReusedSnapshotCount: iterations.filter { $0.sessionMetrics.layoutMode == "reusedSnapshot" }.count,
        layoutIncrementalCount: iterations.filter { $0.sessionMetrics.layoutMode == "incremental" }.count,
        visibleOrderEntryCountMedian: median(
            iterations.map { Double($0.sessionMetrics.visibleOrderEntryCount) }
        ),
        layoutInputBlockCountMedian: median(
            iterations.map { Double($0.sessionMetrics.layoutInputBlockCount) }
        ),
        layoutOutputBlockCountMedian: median(
            iterations.map { Double($0.sessionMetrics.layoutOutputBlockCount) }
        ),
        visibleRenderedBlockCountMedian: median(
            iterations.map { Double($0.visibleRenderedBlockCount) }
        ),
        nonVisibleLayoutInputCountMedian: median(
            iterations.map {
                Double(
                    max(
                        0,
                        $0.sessionMetrics.layoutInputBlockCount
                            - $0.visibleRenderedBlockCount
                    )
                )
            }
        ),
        cacheHitCountMedian: median(
            iterations.map { Double($0.sessionMetrics.cacheHitCount) }
        ),
        cacheMissCountMedian: median(
            iterations.map { Double($0.sessionMetrics.cacheMissCount) }
        ),
        heightIndexRebuildCountMedian: median(
            iterations.map { Double($0.sessionMetrics.heightIndexRebuildCount) }
        ),
        heightIndexInsertCountMedian: median(
            iterations.map { Double($0.sessionMetrics.heightIndexInsertCount) }
        ),
        heightIndexRemoveCountMedian: median(
            iterations.map { Double($0.sessionMetrics.heightIndexRemoveCount) }
        ),
        heightIndexMoveCountMedian: median(
            iterations.map { Double($0.sessionMetrics.heightIndexMoveCount) }
        ),
        heightIndexUpdateHeightCountMedian: median(
            iterations.map { Double($0.sessionMetrics.heightIndexUpdateHeightCount) }
        ),
        damageRectCountMedian: median(iterations.map { Double($0.damageRectCount) }),
        damageAreaMedian: median(iterations.map(\.damageArea)),
        invalidationBlockCountMedian: median(iterations.map { Double($0.invalidationBlockCount) }),
        visibleSequenceChangedCount: iterations.filter(\.visibleSequenceChanged).count,
        layoutGeometryChangedCount: iterations.filter(\.layoutGeometryChanged).count,
        layoutDirtyAfterHandleCount: iterations.filter(\.layoutDirtyAfterHandle).count
    )
}

func nanosecondsToMilliseconds(_ value: UInt64) -> Double {
    Double(value) / 1_000_000.0
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count % 2 == 0 {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

// MARK: - CSV

let csvHeader = [
    "runID",
    "timestamp",
    "gitRevision",
    "configuration",
    "osVersion",
    "processorCount",
    "action",
    "blockCount",
    "targetIndex",
    "viewportWidth",
    "viewportHeight",
    "iterations",
    "documentBlockCountAfterMedian",
    "totalHeightMedian",
    "handleMsMedian",
    "damageMsMedian",
    "renderMsMedian",
    "totalMsMedian",
    "layoutFullRebuildCount",
    "layoutReusedSnapshotCount",
    "layoutIncrementalCount",
    "visibleOrderEntryCountMedian",
    "layoutInputBlockCountMedian",
    "layoutOutputBlockCountMedian",
    "visibleRenderedBlockCountMedian",
    "nonVisibleLayoutInputCountMedian",
    "cacheHitCountMedian",
    "cacheMissCountMedian",
    "heightIndexRebuildCountMedian",
    "heightIndexInsertCountMedian",
    "heightIndexRemoveCountMedian",
    "heightIndexMoveCountMedian",
    "heightIndexUpdateHeightCountMedian",
    "damageRectCountMedian",
    "damageAreaMedian",
    "invalidationBlockCountMedian",
    "visibleSequenceChangedCount",
    "layoutGeometryChangedCount",
    "layoutDirtyAfterHandleCount",
].joined(separator: ",")

func csvRow(
    runID: String,
    timestamp: String,
    options: BenchmarkOptions,
    summary: BenchmarkSummary
) -> String {
    [
        runID,
        timestamp,
        options.gitRevision,
        buildConfiguration(),
        ProcessInfo.processInfo.operatingSystemVersionString,
        String(ProcessInfo.processInfo.processorCount),
        summary.action.rawValue,
        String(summary.blockCount),
        String(summary.targetIndex),
        format(summary.viewportWidth),
        format(summary.viewportHeight),
        String(summary.iterations),
        format(summary.documentBlockCountAfterMedian),
        format(summary.totalHeightMedian),
        format(summary.handleDurationMsMedian),
        format(summary.damageDurationMsMedian),
        format(summary.renderDurationMsMedian),
        format(summary.totalDurationMsMedian),
        String(summary.layoutFullRebuildCount),
        String(summary.layoutReusedSnapshotCount),
        String(summary.layoutIncrementalCount),
        format(summary.visibleOrderEntryCountMedian),
        format(summary.layoutInputBlockCountMedian),
        format(summary.layoutOutputBlockCountMedian),
        format(summary.visibleRenderedBlockCountMedian),
        format(summary.nonVisibleLayoutInputCountMedian),
        format(summary.cacheHitCountMedian),
        format(summary.cacheMissCountMedian),
        format(summary.heightIndexRebuildCountMedian),
        format(summary.heightIndexInsertCountMedian),
        format(summary.heightIndexRemoveCountMedian),
        format(summary.heightIndexMoveCountMedian),
        format(summary.heightIndexUpdateHeightCountMedian),
        format(summary.damageRectCountMedian),
        format(summary.damageAreaMedian),
        format(summary.invalidationBlockCountMedian),
        String(summary.visibleSequenceChangedCount),
        String(summary.layoutGeometryChangedCount),
        String(summary.layoutDirtyAfterHandleCount),
    ].map(csvEscape).joined(separator: ",")
}

func buildConfiguration() -> String {
    #if DEBUG
    return "debug"
    #else
    return "release"
    #endif
}

func format(_ value: Double) -> String {
    String(format: "%.3f", value)
}

func csvEscape(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
}

// MARK: - Main

let options = BenchmarkOptions(arguments: Array(CommandLine.arguments.dropFirst()))
let timestamp = ISO8601DateFormatter().string(from: Date())
let runID = UUID().uuidString

var rows = [csvHeader]
for blockCount in options.blockCounts {
    for action in BenchmarkAction.allCases {
        var iterationResults: [IterationResult] = []
        iterationResults.reserveCapacity(options.iterations)
        for _ in 0..<options.iterations {
            iterationResults.append(runIteration(action: action, blockCount: blockCount))
        }
        let summary = summarize(
            action: action,
            blockCount: blockCount,
            iterations: iterationResults
        )
        rows.append(
            csvRow(runID: runID, timestamp: timestamp, options: options, summary: summary)
        )
    }
}

let output = rows.joined(separator: "\n") + "\n"
if let outputPath = options.outputPath {
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try output.write(to: url, atomically: true, encoding: .utf8)
} else {
    print(output, terminator: "")
}

#else

import Darwin

fputs(
    "Build SlopadSessionBenchmark with -Xswiftc -DSLOPAD_BENCHMARK_INSTRUMENTATION\n",
    stderr
)
exit(1)
#endif
