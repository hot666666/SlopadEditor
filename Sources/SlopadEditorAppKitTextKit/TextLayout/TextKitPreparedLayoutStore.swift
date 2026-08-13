import AppKit
import Foundation
import SlopadEditorCoreModel

// MARK: - Store Policy

struct TextKitPreparedLayoutStorePolicy: Equatable, Sendable {
    /// Default selected by #37's release AppKit UI benchmark sweep.
    static let productionDefault = TextKitPreparedLayoutStorePolicy(
        entryLimit: 96,
        estimatedCostLimit: 6 * 1_024 * 1_024
    )

    let entryLimit: Int
    let estimatedCostLimit: Int

    init(entryLimit: Int, estimatedCostLimit: Int) {
        self.entryLimit = max(1, entryLimit)
        self.estimatedCostLimit = max(1, estimatedCostLimit)
    }

    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        static func benchmarkConfigured(
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> TextKitPreparedLayoutStorePolicy {
            let entryLimit = environment["SLOPAD_TEXTKIT_PREPARED_ENTRY_LIMIT"]
                .flatMap(Int.init) ?? productionDefault.entryLimit
            let estimatedCostLimit = environment["SLOPAD_TEXTKIT_PREPARED_COST_LIMIT"]
                .flatMap(Int.init) ?? productionDefault.estimatedCostLimit
            return TextKitPreparedLayoutStorePolicy(
                entryLimit: entryLimit,
                estimatedCostLimit: estimatedCostLimit
            )
        }
    #endif
}

// MARK: - Prepared Entry

struct TextKitPreparedLayoutKey: Hashable {
    let request: BlockMeasureRequest
    let style: TextKitEditorStyle
}

final class TextKitPreparedLayoutState {
    let key: TextKitPreparedLayoutKey
    let canonicalText: String
    let layoutText: String
    let layoutUTF16Count: Int
    let estimatedCost: Int

    let textStorage = NSTextStorage()
    let textContentStorage = NSTextContentStorage()
    let textLayoutManager = NSTextLayoutManager()
    let textContainer: NSTextContainer

    // Measurement and drawing do not need index conversion. Build these arrays only
    // when geometry/navigation first crosses the grapheme-to-UTF-16 boundary.
    lazy var canonicalIndexMap = TextKitTextIndexMap(text: canonicalText)
    lazy var layoutIndexMap = layoutText == canonicalText
        ? canonicalIndexMap
        : TextKitTextIndexMap(text: layoutText)

    init(
        key: TextKitPreparedLayoutKey,
        attributedString: NSAttributedString,
        textWidth: CGFloat
    ) {
        self.key = key
        self.canonicalText = key.request.text
        self.layoutText = attributedString.string
        self.layoutUTF16Count = attributedString.length
        self.estimatedCost = Self.estimatedCost(
            request: key.request,
            layoutUTF16Count: attributedString.length
        )
        self.textContainer = NSTextContainer(
            size: CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
        )

        textContainer.lineFragmentPadding = 0
        textContentStorage.textStorage = textStorage
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textLayoutManager.textContainer = textContainer
        textLayoutManager.textSelectionNavigation.allowsNonContiguousRanges = false
        textStorage.setAttributedString(attributedString)
        textLayoutManager.textSelectionNavigation.flushLayoutCache()
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        // Each entry is width-specific. Preserve the prior single-slot miss behavior that
        // rebuilt navigation after a width change; TextKit otherwise retains stale bidi
        // visual-caret order even though layout itself is current.
        textLayoutManager.textSelectionNavigation = NSTextSelectionNavigation(
            dataSource: textLayoutManager
        )
    }

    private static func estimatedCost(
        request: BlockMeasureRequest,
        layoutUTF16Count: Int
    ) -> Int {
        // TextKit does not expose its glyph/layout allocation size. This deliberately named
        // estimate supplies a strict accounting bound for retained inputs and native graph
        // count; process footprint remains a separate benchmark metric.
        let nativeGraphAllowance = 64 * 1_024
        let textBytes = request.text.utf8.count + layoutUTF16Count * MemoryLayout<UInt16>.size
        let inlineRunAllowance = request.inlineRuns.count * 128
        return nativeGraphAllowance + textBytes + inlineRunAllowance
    }
}

// MARK: - Store Instrumentation

struct TextKitPreparedLayoutStoreSnapshot: Equatable, Sendable {
    var lookups = 0
    var hits = 0
    var prepares = 0
    var attributedStringBuilds = 0
    var capacityEvictions = 0
    var capacityRejections = 0
    var pressureEvictions = 0
    var invalidationRemovals = 0
    var oversizedPinnedInsertions = 0
    var residentEntryCount = 0
    var residentEstimatedCost = 0
    var residentEntryHighWater = 0
    var residentEstimatedCostHighWater = 0
    var pinnedEntryCount = 0
    var isOverEstimatedCostLimit = false
    var pinnedBlockIDAtLastPrepare: BlockID?
}

#if SLOPAD_BENCHMARK_INSTRUMENTATION
    package struct TextKitPreparedLayoutInstrumentationSnapshot: Equatable, Sendable {
        package var lookups: Int
        package var hits: Int
        package var prepares: Int
        package var attributedStringBuilds: Int
        package var capacityEvictions: Int
        package var capacityRejections: Int
        package var pressureEvictions: Int
        package var invalidationRemovals: Int
        package var oversizedPinnedInsertions: Int
        package var residentEntryCount: Int
        package var residentEstimatedCost: Int
        package var residentEntryHighWater: Int
        package var residentEstimatedCostHighWater: Int
        package var pinnedEntryCount: Int
        package var overEstimatedCostLimitContextCount: Int
        package var pinnedBlockIDAtLastPrepare: BlockID?

        init(_ snapshot: TextKitPreparedLayoutStoreSnapshot) {
            lookups = snapshot.lookups
            hits = snapshot.hits
            prepares = snapshot.prepares
            attributedStringBuilds = snapshot.attributedStringBuilds
            capacityEvictions = snapshot.capacityEvictions
            capacityRejections = snapshot.capacityRejections
            pressureEvictions = snapshot.pressureEvictions
            invalidationRemovals = snapshot.invalidationRemovals
            oversizedPinnedInsertions = snapshot.oversizedPinnedInsertions
            residentEntryCount = snapshot.residentEntryCount
            residentEstimatedCost = snapshot.residentEstimatedCost
            residentEntryHighWater = snapshot.residentEntryHighWater
            residentEstimatedCostHighWater = snapshot.residentEstimatedCostHighWater
            pinnedEntryCount = snapshot.pinnedEntryCount
            overEstimatedCostLimitContextCount = snapshot.isOverEstimatedCostLimit ? 1 : 0
            pinnedBlockIDAtLastPrepare = snapshot.pinnedBlockIDAtLastPrepare
        }

        package static let zero = TextKitPreparedLayoutInstrumentationSnapshot(
            TextKitPreparedLayoutStoreSnapshot()
        )
    }
#endif

package enum TextKitPreparedLayoutMemoryPressure: Sendable {
    case warning
    case critical
}

// MARK: - Prepared Store

struct TextKitPreparedLayoutStore {
    private(set) var snapshot = TextKitPreparedLayoutStoreSnapshot()

    private let policy: TextKitPreparedLayoutStorePolicy
    private var entries: [TextKitPreparedLayoutKey: TextKitPreparedLayoutState] = [:]
    /// Oldest to newest. The small, explicitly bounded collection keeps this deterministic
    /// without adding another dependency or a second mutable linked structure.
    private var recency: [TextKitPreparedLayoutKey] = []
    private var pinnedBlockID: BlockID?

    init(policy: TextKitPreparedLayoutStorePolicy) {
        self.policy = policy
    }

    mutating func preparedLayout(
        for key: TextKitPreparedLayoutKey,
        makeEntry: () -> TextKitPreparedLayoutState
    ) -> TextKitPreparedLayoutState {
        snapshot.lookups += 1
        if let entry = entries[key] {
            snapshot.hits += 1
            markMostRecent(key)
            refreshGauges()
            return entry
        }

        snapshot.prepares += 1
        snapshot.pinnedBlockIDAtLastPrepare = pinnedBlockID
        let entry = makeEntry()
        snapshot.attributedStringBuilds += 1

        let replacementKeys = recency.filter { $0.request.blockID == key.request.blockID }
        let isPinned = key.request.blockID == pinnedBlockID
        let fitsCost = entry.estimatedCost <= policy.estimatedCostLimit
        guard
            let evictionPlan = capacityEvictionPlan(
                for: entry,
                replacing: replacementKeys,
                permitsOversizedPinnedEntry: isPinned && !fitsCost
            )
        else {
            // A new revision invalidates its own stale resident, but an impossible candidate
            // must not pollute the cache by evicting unrelated useful entries before it is
            // rejected.
            for replacementKey in replacementKeys {
                remove(replacementKey, reason: .invalidation)
            }
            snapshot.capacityRejections += 1
            refreshGauges()
            return entry
        }

        for replacementKey in replacementKeys {
            remove(replacementKey, reason: .invalidation)
        }
        for victim in evictionPlan {
            remove(victim, reason: .capacity)
        }
        entries[key] = entry
        recency.append(key)
        if isPinned, !fitsCost {
            snapshot.oversizedPinnedInsertions += 1
        }
        refreshGauges()
        updateHighWaterMarks()
        return entry
    }

    mutating func setPinnedBlockID(_ blockID: BlockID?) {
        pinnedBlockID = blockID
        enforceCapacity()
        refreshGauges()
    }

    mutating func removeAllForInvalidation() {
        snapshot.invalidationRemovals += entries.count
        entries.removeAll(keepingCapacity: true)
        recency.removeAll(keepingCapacity: true)
        refreshGauges()
    }

    mutating func handleMemoryPressure(_ pressure: TextKitPreparedLayoutMemoryPressure) {
        switch pressure {
        case .warning:
            let retainedBlockID = pinnedBlockID
            removeEntries(
                where: { $0.request.blockID != retainedBlockID },
                reason: .pressure
            )
        case .critical:
            snapshot.pressureEvictions += entries.count
            entries.removeAll(keepingCapacity: true)
            recency.removeAll(keepingCapacity: true)
        }
        refreshGauges()
    }

    private func capacityEvictionPlan(
        for entry: TextKitPreparedLayoutState,
        replacing replacementKeys: [TextKitPreparedLayoutKey],
        permitsOversizedPinnedEntry: Bool
    ) -> [TextKitPreparedLayoutKey]? {
        let replacements = Set(replacementKeys)
        var simulatedCount = entries.count - replacements.count
        var simulatedCost = currentEstimatedCost - replacementKeys.reduce(into: 0) {
            $0 += entries[$1]?.estimatedCost ?? 0
        }
        var victims: [TextKitPreparedLayoutKey] = []

        for candidate in recency
        where !replacements.contains(candidate) && candidate.request.blockID != pinnedBlockID {
            let countFits = simulatedCount + 1 <= policy.entryLimit
            let costFits = simulatedCost + entry.estimatedCost <= policy.estimatedCostLimit
            if countFits && costFits { break }

            simulatedCount -= 1
            simulatedCost -= entries[candidate]?.estimatedCost ?? 0
            victims.append(candidate)
        }

        let countFits = simulatedCount + 1 <= policy.entryLimit
        let costFits = simulatedCost + entry.estimatedCost <= policy.estimatedCostLimit
        if countFits && costFits {
            return victims
        }
        if permitsOversizedPinnedEntry, countFits, simulatedCount == 0 {
            return victims
        }
        return nil
    }

    private mutating func enforceCapacity() {
        while entries.count > policy.entryLimit
            || currentEstimatedCost > policy.estimatedCostLimit
        {
            guard let victim = leastRecentUnpinnedKey() else { break }
            remove(victim, reason: .capacity)
        }
    }

    private func leastRecentUnpinnedKey() -> TextKitPreparedLayoutKey? {
        recency.first { $0.request.blockID != pinnedBlockID }
    }

    private mutating func markMostRecent(_ key: TextKitPreparedLayoutKey) {
        if let index = recency.firstIndex(of: key) {
            recency.remove(at: index)
        }
        recency.append(key)
    }

    private enum RemovalReason {
        case capacity
        case pressure
        case invalidation
    }

    private mutating func removeEntries(
        where shouldRemove: (TextKitPreparedLayoutKey) -> Bool,
        reason: RemovalReason
    ) {
        for key in recency.filter(shouldRemove) {
            remove(key, reason: reason)
        }
    }

    private mutating func remove(_ key: TextKitPreparedLayoutKey, reason: RemovalReason) {
        guard entries.removeValue(forKey: key) != nil else { return }
        if let index = recency.firstIndex(of: key) {
            recency.remove(at: index)
        }
        switch reason {
        case .capacity:
            snapshot.capacityEvictions += 1
        case .pressure:
            snapshot.pressureEvictions += 1
        case .invalidation:
            snapshot.invalidationRemovals += 1
        }
    }

    private var currentEstimatedCost: Int {
        entries.values.reduce(into: 0) { $0 += $1.estimatedCost }
    }

    private mutating func refreshGauges() {
        snapshot.residentEntryCount = entries.count
        snapshot.residentEstimatedCost = currentEstimatedCost
        snapshot.pinnedEntryCount = entries.values.filter {
            $0.key.request.blockID == pinnedBlockID
        }.count
        snapshot.isOverEstimatedCostLimit =
            snapshot.residentEstimatedCost > policy.estimatedCostLimit
    }

    private mutating func updateHighWaterMarks() {
        snapshot.residentEntryHighWater = max(
            snapshot.residentEntryHighWater,
            snapshot.residentEntryCount
        )
        snapshot.residentEstimatedCostHighWater = max(
            snapshot.residentEstimatedCostHighWater,
            snapshot.residentEstimatedCost
        )
    }
}
