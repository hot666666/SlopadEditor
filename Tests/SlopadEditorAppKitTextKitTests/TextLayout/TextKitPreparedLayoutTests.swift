import CoreGraphics
import Dispatch
import Foundation
import SlopadEditorCoreModel
import Testing

@testable import SlopadEditorAppKitTextKit

// MARK: - Prepared layout reuse

@Suite("prepared layout 저장소")
struct TextKitPreparedLayoutTests {
    @Test("renderer가 그린 요청을 layouter가 같은 geometry로 이어받는다")
    func rendererThenLayouterUsesCoherentGeometry() throws {
        // Given
        let system = TextKitTextSystem()
        let request = makeRequest(text: "Body text")
        let context = try #require(makeBitmapContext())

        // When
        system.renderer.draw(
            request,
            in: CGRect(x: 0, y: 0, width: 320, height: 120),
            context: context
        )
        let caret = system.layouter.caretRect(
            for: TextPosition(blockID: request.blockID, offset: 2),
            in: request
        )

        // Then
        #expect(caret != nil)
        #expect(system.layouter.measure(request).height > 0)
    }

    @Test("A B C A 순회에서도 축출 전후 결과가 동일하다")
    func coldHitAndEvictedResultsAreEquivalent() throws {
        // Given
        let system = TextKitTextSystem(
            preparedLayoutPolicy: TextKitPreparedLayoutStorePolicy(
                entryLimit: 2,
                estimatedCostLimit: 16 * 1_024 * 1_024
            )
        )
        let a = makeRequest(blockID: "a", text: "abc אבג 👨‍👩‍👧‍👦\n")
        let b = makeRequest(blockID: "b", text: "second block")
        let c = makeRequest(blockID: "c", text: "third block")

        // When
        let cold = try observables(system: system, request: a)
        let hit = try observables(system: system, request: a)
        _ = system.layouter.measure(b)
        _ = system.layouter.measure(c)
        let afterEviction = try observables(system: system, request: a)

        // Then
        #expect(cold.measurement == hit.measurement)
        #expect(cold.measurement == afterEviction.measurement)
        #expect(cold.fragments == hit.fragments)
        #expect(cold.fragments == afterEviction.fragments)
        #expect(cold.caret == hit.caret)
        #expect(cold.caret == afterEviction.caret)
        #expect(cold.selectionRects == hit.selectionRects)
        #expect(cold.selectionRects == afterEviction.selectionRects)
        #expect(cold.hitTest == hit.hitTest)
        #expect(cold.hitTest == afterEviction.hitTest)
        #expect(cold.navigation == hit.navigation)
        #expect(cold.navigation == afterEviction.navigation)
        #expect(cold.wordRange == hit.wordRange)
        #expect(cold.wordRange == afterEviction.wordRange)
        #expect(cold.deletionRange == hit.deletionRange)
        #expect(cold.deletionRange == afterEviction.deletionRange)
        #expect(cold.drawBytes == hit.drawBytes)
        #expect(cold.drawBytes == afterEviction.drawBytes)
    }

    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        @Test("동일 exact key 조회는 lookup과 hit만 증가시킨다")
        func exactKeyHitCounterSemantics() {
            // Given
            let system = makeSystem(entryLimit: 3)
            let request = makeRequest(text: "Body text")

            // When
            _ = system.layouter.measure(request)
            _ = system.layouter.measure(request)
            let snapshot = system.layouter.contextPreparedLayoutInstrumentation

            // Then
            #expect(snapshot.lookups == 2)
            #expect(snapshot.hits == 1)
            #expect(snapshot.prepares == 1)
            #expect(snapshot.attributedStringBuilds == 1)
            #expect(snapshot.residentEntryCount == 1)
        }

        @Test("A B C A의 deterministic LRU는 두 번 축출하고 네 번 준비한다")
        func deterministicLRUCounterSemantics() {
            // Given
            let system = makeSystem(entryLimit: 2)
            let requests = [
                makeRequest(blockID: "a", text: "a"),
                makeRequest(blockID: "b", text: "b"),
                makeRequest(blockID: "c", text: "c"),
                makeRequest(blockID: "a", text: "a"),
            ]

            // When
            for request in requests {
                _ = system.layouter.measure(request)
            }
            let snapshot = system.layouter.contextPreparedLayoutInstrumentation

            // Then
            #expect(snapshot.lookups == 4)
            #expect(snapshot.hits == 0)
            #expect(snapshot.prepares == 4)
            #expect(snapshot.attributedStringBuilds == 4)
            #expect(snapshot.capacityEvictions == 2)
            #expect(snapshot.residentEntryCount == 2)
            #expect(snapshot.residentEntryHighWater == 2)
        }

        @Test("같은 BlockID의 새 revision은 이전 exact key를 교체한다")
        func sameBlockNewRevisionReplacesOldKey() {
            // Given
            let system = makeSystem(entryLimit: 8)
            let original = makeRequest(blockID: "active", text: "before", width: 320)
            let changedText = makeRequest(blockID: "active", text: "after", width: 320)
            let changedWidth = makeRequest(blockID: "active", text: "after", width: 480)

            // When
            _ = system.layouter.measure(original)
            _ = system.layouter.measure(changedText)
            _ = system.layouter.measure(changedWidth)
            let snapshot = system.layouter.contextPreparedLayoutInstrumentation

            // Then
            #expect(snapshot.prepares == 3)
            #expect(snapshot.invalidationRemovals == 2)
            #expect(snapshot.residentEntryCount == 1)
        }

        @Test("text kind inline width depth style mutation은 모두 exact key를 갱신한다")
        func mutationAxesReplaceExactKey() {
            // Given
            let context = TextKitLayoutContext(
                policy: TextKitPreparedLayoutStorePolicy(
                    entryLimit: 8,
                    estimatedCostLimit: 16 * 1_024 * 1_024
                )
            )
            let blockID: BlockID = "same"
            let requests = [
                makeRequest(blockID: blockID, text: "plain"),
                makeRequest(blockID: blockID, text: "changed"),
                makeRequest(blockID: blockID, text: "changed", width: 480),
                makeRequest(blockID: blockID, text: "changed", kind: .heading(level: .h2)),
                makeRequest(
                    blockID: blockID,
                    text: "changed",
                    inlineRuns: [
                        BlockContent.InlineRun(
                            range: TextRange(0, 7),
                            text: "changed",
                            marks: [.code]
                        )
                    ]
                ),
                makeRequest(blockID: blockID, text: "changed", depth: 2),
            ]

            // When
            for request in requests {
                _ = context.measure(request, style: TextKitEditorStyle(), minimumHeight: 1)
            }
            _ = context.measure(
                requests.last!,
                style: TextKitEditorStyle(fontSize: 18),
                minimumHeight: 1
            )
            let snapshot = context.instrumentationSnapshot()

            // Then
            #expect(snapshot.prepares == 7)
            #expect(snapshot.invalidationRemovals == 6)
            #expect(snapshot.residentEntryCount == 1)
        }

        @Test("active BlockID pin은 새 request로 이동하고 warning에서 유지된다")
        func activePinTransfersAndSurvivesWarningPressure() {
            // Given
            let system = makeSystem(entryLimit: 1)
            let firstRevision = makeRequest(blockID: "active", text: "가")
            let secondRevision = makeRequest(blockID: "active", text: "가나")
            let inactive = makeRequest(blockID: "inactive", text: "other")
            system.setActivePreparedLayoutBlockID(firstRevision.blockID)

            // When
            _ = system.layouter.measure(firstRevision)
            _ = system.layouter.measure(secondRevision)
            _ = system.layouter.measure(inactive)
            system.handlePreparedLayoutMemoryPressure(.warning)
            _ = system.layouter.measure(secondRevision)
            let snapshot = system.layouter.contextPreparedLayoutInstrumentation

            // Then
            #expect(snapshot.hits == 1)
            #expect(snapshot.pinnedEntryCount == 1)
            #expect(snapshot.residentEntryCount == 1)
            #expect(snapshot.pressureEvictions == 0)
        }

        @Test("IME active pin handoff 뒤에는 새 블록만 warning에서 남는다")
        func imePinHandoffRetainsOnlyNewActiveBlock() {
            // Given
            let system = makeSystem(entryLimit: 2)
            let first = makeRequest(blockID: "first", text: "조합 중")
            let second = makeRequest(blockID: "second", text: "다음 조합")
            system.setActivePreparedLayoutBlockID(first.blockID)
            _ = system.layouter.measure(first)
            _ = system.layouter.measure(second)

            // When
            system.setActivePreparedLayoutBlockID(second.blockID)
            system.handlePreparedLayoutMemoryPressure(.warning)
            _ = system.layouter.measure(second)
            let snapshot = system.layouter.contextPreparedLayoutInstrumentation

            // Then
            #expect(snapshot.hits == 1)
            #expect(snapshot.pressureEvictions == 1)
            #expect(snapshot.residentEntryCount == 1)
            #expect(snapshot.pinnedEntryCount == 1)
        }

        @Test("critical pressure는 pin도 제거하고 다음 조회를 다시 준비한다")
        func criticalPressurePurgesPinnedEntry() {
            // Given
            let system = makeSystem(entryLimit: 2)
            let request = makeRequest(blockID: "active", text: "active")
            system.setActivePreparedLayoutBlockID(request.blockID)
            _ = system.layouter.measure(request)

            // When
            system.handlePreparedLayoutMemoryPressure(.critical)
            _ = system.layouter.measure(request)
            let snapshot = system.layouter.contextPreparedLayoutInstrumentation

            // Then
            #expect(snapshot.prepares == 2)
            #expect(snapshot.pressureEvictions == 1)
            #expect(snapshot.residentEntryCount == 1)
            #expect(snapshot.pinnedEntryCount == 1)
        }

        @Test("명시적 lifecycle invalidation은 resident entry를 모두 제거한다")
        func lifecycleInvalidationClearsResidents() {
            // Given
            let system = makeSystem(entryLimit: 4)
            let first = makeRequest(blockID: "first", text: "first")
            let second = makeRequest(blockID: "second", text: "second")
            _ = system.layouter.measure(first)
            _ = system.layouter.measure(second)

            // When
            system.removeAllPreparedLayouts()
            _ = system.layouter.measure(first)
            let snapshot = system.layouter.contextPreparedLayoutInstrumentation

            // Then
            #expect(snapshot.invalidationRemovals == 2)
            #expect(snapshot.prepares == 3)
            #expect(snapshot.residentEntryCount == 1)
        }

        @Test("비활성 oversized entry는 strict cost cap 밖에 보관하지 않는다")
        func oversizedInactiveEntryIsNotRetained() {
            // Given
            let system = TextKitTextSystem(
                preparedLayoutPolicy: TextKitPreparedLayoutStorePolicy(
                    entryLimit: 8,
                    estimatedCostLimit: 1
                )
            )
            let request = makeRequest(text: "oversized")

            // When
            _ = system.layouter.measure(request)
            _ = system.layouter.measure(request)
            let snapshot = system.layouter.contextPreparedLayoutInstrumentation

            // Then
            #expect(snapshot.prepares == 2)
            #expect(snapshot.capacityEvictions == 0)
            #expect(snapshot.capacityRejections == 2)
            #expect(snapshot.residentEntryCount == 0)
            #expect(snapshot.residentEstimatedCost == 0)
        }

        @Test("active oversized entry 하나만 budget overrun 예외로 계측한다")
        func oneOversizedActiveEntryIsMeasuredException() {
            // Given
            let system = TextKitTextSystem(
                preparedLayoutPolicy: TextKitPreparedLayoutStorePolicy(
                    entryLimit: 8,
                    estimatedCostLimit: 1
                )
            )
            let request = makeRequest(blockID: "active", text: "oversized active")
            system.setActivePreparedLayoutBlockID(request.blockID)

            // When
            _ = system.layouter.measure(request)
            let snapshot = system.layouter.contextPreparedLayoutInstrumentation

            // Then
            #expect(snapshot.oversizedPinnedInsertions == 1)
            #expect(snapshot.residentEntryCount == 1)
            #expect(snapshot.pinnedEntryCount == 1)
            #expect(snapshot.residentEstimatedCost > 1)
            #expect(snapshot.overEstimatedCostLimitContextCount == 1)
        }

        @Test("동시 same-key 조회는 하나만 준비하고 counter를 잃지 않는다")
        func concurrentSameKeyLookupIsThreadSafe() {
            // Given
            let system = makeSystem(entryLimit: 4)
            let request = makeRequest(text: "concurrent 👨‍👩‍👧‍👦")
            let lookupCount = 64

            // When
            DispatchQueue.concurrentPerform(iterations: lookupCount) { _ in
                _ = system.layouter.measure(request)
            }
            let snapshot = system.layouter.contextPreparedLayoutInstrumentation

            // Then
            #expect(snapshot.lookups == lookupCount)
            #expect(snapshot.hits == lookupCount - 1)
            #expect(snapshot.prepares == 1)
            #expect(snapshot.attributedStringBuilds == 1)
            #expect(snapshot.residentEntryCount == 1)
        }

        @Test("renderer와 layouter의 production 조립은 하나의 저장소를 공유한다")
        func rendererThenLayouterReusesOnePreparedState() throws {
            // Given
            let system = TextKitTextSystem()
            let request = makeRequest(text: "Body text")
            let context = try #require(makeBitmapContext())

            // When
            system.renderer.draw(
                request,
                in: CGRect(x: 0, y: 0, width: 320, height: 120),
                context: context
            )
            _ = system.layouter.caretRect(
                for: TextPosition(blockID: request.blockID, offset: 2),
                in: request
            )

            // Then
            #expect(
                system.layouter.layoutContextIdentifierForInstrumentation
                    == system.renderer.layoutContextIdentifierForInstrumentation
            )
            let snapshot = system.layouter.contextPreparedLayoutInstrumentation
            #expect(snapshot.lookups == 2)
            #expect(snapshot.hits == 1)
            #expect(snapshot.prepares == 1)
            #expect(snapshot.attributedStringBuilds == 1)
        }
    #endif

    // MARK: - Support

    private struct Observables {
        let measurement: BlockMeasurement
        let fragments: [LineFragmentSnapshot]
        let caret: EditorRect?
        let selectionRects: [EditorRect]
        let hitTest: TextHitTestResult?
        let navigation: TextNavigationResolution
        let wordRange: SlopadEditorCoreModel.TextRange?
        let deletionRange: SlopadEditorCoreModel.TextRange?
        let drawBytes: [UInt8]
    }

    private func observables(
        system: TextKitTextSystem,
        request: BlockMeasureRequest
    ) throws -> Observables {
        let upperBound = min(3, request.text.count)
        let measurement = system.layouter.measure(request)
        let fragments = system.layouter.lineFragments(for: request)
        let caret = system.layouter.caretRect(
            for: TextPosition(blockID: request.blockID, offset: upperBound),
            in: request
        )
        let selection = TextSelection(
            anchor: TextPosition(blockID: request.blockID, offset: upperBound),
            focus: TextPosition(blockID: request.blockID, offset: upperBound)
        )
        let hitPoint = fragments.first.map {
            EditorPoint(x: $0.rect.x + 2, y: $0.rect.y + $0.rect.height * 0.5)
        } ?? EditorPoint(x: 0, y: 0)
        return Observables(
            measurement: measurement,
            fragments: fragments,
            caret: caret,
            selectionRects: system.layouter.selectionRects(
                for: TextRange(0, upperBound),
                in: request
            ),
            hitTest: system.layouter.textHitTest(at: hitPoint, in: request),
            navigation: system.layouter.navigate(
                selection: selection,
                context: nil,
                direction: .right,
                destination: .character,
                extending: false,
                in: request
            ),
            wordRange: system.layouter.wordRange(
                containing: selection.focus,
                in: request
            ),
            deletionRange: system.layouter.deletionRange(
                for: selection,
                direction: .backward,
                destination: .character,
                in: request
            ),
            drawBytes: try drawBytes(system: system, request: request)
        )
    }

    private func drawBytes(
        system: TextKitTextSystem,
        request: BlockMeasureRequest
    ) throws -> [UInt8] {
        let width = 640
        let height = 240
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            system.renderer.draw(
                request,
                in: CGRect(x: 0, y: 0, width: width, height: height),
                context: context
            )
        }
        return bytes
    }

    private func makeSystem(entryLimit: Int) -> TextKitTextSystem {
        TextKitTextSystem(
            preparedLayoutPolicy: TextKitPreparedLayoutStorePolicy(
                entryLimit: entryLimit,
                estimatedCostLimit: 16 * 1_024 * 1_024
            )
        )
    }

    private func makeRequest(
        blockID: BlockID = "block",
        text: String,
        width: Double = 320,
        kind: BlockKind = .paragraph,
        inlineRuns: [BlockContent.InlineRun] = [],
        depth: Int = 0
    ) -> BlockMeasureRequest {
        BlockMeasureRequest(
            blockID: blockID,
            text: text,
            kind: kind,
            inlineRuns: inlineRuns,
            availableWidth: width,
            depth: depth
        )
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

@Suite("prepared layout store 기본 정책")
struct TextKitPreparedLayoutStorePolicyTests {
    @Test("기본 빌드에서도 exact key hit와 deterministic LRU를 검증한다")
    func exactKeyAndLRU() {
        // Given
        var store = makeStore(entryLimit: 2)
        let a = makeKey(blockID: "a", text: "a")
        let b = makeKey(blockID: "b", text: "b")
        let c = makeKey(blockID: "c", text: "c")

        // When
        access(a, in: &store)
        access(b, in: &store)
        access(a, in: &store)
        access(c, in: &store)
        access(b, in: &store)

        // Then
        #expect(store.snapshot.lookups == 5)
        #expect(store.snapshot.hits == 1)
        #expect(store.snapshot.prepares == 4)
        #expect(store.snapshot.capacityEvictions == 2)
        #expect(store.snapshot.capacityRejections == 0)
        #expect(store.snapshot.residentEntryCount == 2)
    }

    @Test("같은 BlockID의 새 exact key는 이전 revision만 교체한다")
    func sameBlockIDReplacesRevision() {
        // Given
        var store = makeStore(entryLimit: 4)
        let original = makeKey(blockID: "same", text: "before")
        let revision = makeKey(blockID: "same", text: "after")

        // When
        access(original, in: &store)
        access(revision, in: &store)
        access(revision, in: &store)

        // Then
        #expect(store.snapshot.prepares == 2)
        #expect(store.snapshot.hits == 1)
        #expect(store.snapshot.invalidationRemovals == 1)
        #expect(store.snapshot.residentEntryCount == 1)
    }

    @Test("보관 불가능한 oversized miss는 기존 LRU를 오염시키지 않는다")
    func oversizedRejectionPreservesResidents() {
        // Given
        var store = TextKitPreparedLayoutStore(
            policy: TextKitPreparedLayoutStorePolicy(
                entryLimit: 2,
                estimatedCostLimit: 140 * 1_024
            )
        )
        let a = makeKey(blockID: "a", text: "a")
        let b = makeKey(blockID: "b", text: "b")
        let oversized = makeKey(blockID: "oversized", text: String(repeating: "x", count: 100_000))
        access(a, in: &store)
        access(b, in: &store)

        // When
        access(oversized, in: &store)
        access(a, in: &store)
        access(b, in: &store)

        // Then
        #expect(store.snapshot.capacityRejections == 1)
        #expect(store.snapshot.capacityEvictions == 0)
        #expect(store.snapshot.hits == 2)
        #expect(store.snapshot.residentEntryCount == 2)
    }

    @Test("pinned working set과 함께 못 들어가는 miss도 unrelated resident를 보존한다")
    func pinnedCapacityRejectionPreservesUnrelatedResident() {
        // Given
        var store = TextKitPreparedLayoutStore(
            policy: TextKitPreparedLayoutStorePolicy(
                entryLimit: 3,
                estimatedCostLimit: 200 * 1_024
            )
        )
        let pinned = makeKey(blockID: "pinned", text: "pinned")
        let resident = makeKey(blockID: "resident", text: "resident")
        let candidate = makeKey(
            blockID: "candidate",
            text: String(repeating: "c", count: 30_000)
        )
        store.setPinnedBlockID(pinned.request.blockID)
        access(pinned, in: &store)
        access(resident, in: &store)

        // When
        access(candidate, in: &store)
        access(pinned, in: &store)
        access(resident, in: &store)

        // Then
        #expect(store.snapshot.capacityRejections == 1)
        #expect(store.snapshot.capacityEvictions == 0)
        #expect(store.snapshot.hits == 2)
        #expect(store.snapshot.residentEntryCount == 2)
        #expect(store.snapshot.pinnedEntryCount == 1)
    }

    @Test("active pin은 warning에서 남고 critical에서는 제거된다")
    func pinAndPressurePolicy() {
        // Given
        var store = makeStore(entryLimit: 3)
        let active = makeKey(blockID: "active", text: "active")
        let inactive = makeKey(blockID: "inactive", text: "inactive")
        store.setPinnedBlockID(active.request.blockID)
        access(active, in: &store)
        access(inactive, in: &store)

        // When
        store.handleMemoryPressure(.warning)
        access(active, in: &store)
        store.handleMemoryPressure(.critical)
        access(active, in: &store)

        // Then
        #expect(store.snapshot.pressureEvictions == 2)
        #expect(store.snapshot.hits == 1)
        #expect(store.snapshot.prepares == 3)
        #expect(store.snapshot.residentEntryCount == 1)
        #expect(store.snapshot.pinnedEntryCount == 1)
    }

    @Test("oversized active 하나만 cost bound 예외로 허용한다")
    func oversizedActiveExceptionIsSingleResident() {
        // Given
        var store = TextKitPreparedLayoutStore(
            policy: TextKitPreparedLayoutStorePolicy(
                entryLimit: 4,
                estimatedCostLimit: 1
            )
        )
        let active = makeKey(blockID: "active", text: "active")
        let inactive = makeKey(blockID: "inactive", text: "inactive")
        store.setPinnedBlockID(active.request.blockID)

        // When
        access(active, in: &store)
        access(inactive, in: &store)

        // Then
        #expect(store.snapshot.oversizedPinnedInsertions == 1)
        #expect(store.snapshot.capacityRejections == 1)
        #expect(store.snapshot.residentEntryCount == 1)
        #expect(store.snapshot.pinnedEntryCount == 1)
        #expect(store.snapshot.isOverEstimatedCostLimit)
    }

    @Test("policy는 count와 estimated cost limit을 양수로 고정한다")
    func policyClampsBounds() {
        // Given / When
        let policy = TextKitPreparedLayoutStorePolicy(entryLimit: 0, estimatedCostLimit: 0)

        // Then
        #expect(policy.entryLimit == 1)
        #expect(policy.estimatedCostLimit == 1)
    }

    @Test("생산 기본 policy는 benchmark knee인 96개와 6 MiB를 사용한다")
    func productionDefaultMatchesSelectedBenchmarkKnee() {
        // Given / When
        let policy = TextKitPreparedLayoutStorePolicy.productionDefault

        // Then
        #expect(policy.entryLimit == 96)
        #expect(policy.estimatedCostLimit == 6 * 1_024 * 1_024)
    }

    #if SLOPAD_BENCHMARK_INSTRUMENTATION
        @Test("benchmark override가 없으면 생산 기본 policy와 동일하다")
        func benchmarkFallbackMatchesProductionDefault() {
            // Given / When
            let policy = TextKitPreparedLayoutStorePolicy.benchmarkConfigured(environment: [:])

            // Then
            #expect(policy == .productionDefault)
        }
    #endif

    private func makeStore(entryLimit: Int) -> TextKitPreparedLayoutStore {
        TextKitPreparedLayoutStore(
            policy: TextKitPreparedLayoutStorePolicy(
                entryLimit: entryLimit,
                estimatedCostLimit: 16 * 1_024 * 1_024
            )
        )
    }

    private func makeKey(blockID: BlockID, text: String) -> TextKitPreparedLayoutKey {
        TextKitPreparedLayoutKey(
            request: BlockMeasureRequest(
                blockID: blockID,
                text: text,
                kind: .paragraph,
                availableWidth: 320,
                depth: 0
            ),
            style: TextKitEditorStyle()
        )
    }

    private func access(
        _ key: TextKitPreparedLayoutKey,
        in store: inout TextKitPreparedLayoutStore
    ) {
        _ = store.preparedLayout(for: key) {
            let attributedString = TextKitAttributedStringBuilder.attributedString(
                for: key.request,
                style: key.style
            )
            return TextKitPreparedLayoutState(
                key: key,
                attributedString: attributedString,
                textWidth: key.style.textWidth(
                    availableWidth: key.request.availableWidth,
                    depth: key.request.depth
                )
            )
        }
    }
}
