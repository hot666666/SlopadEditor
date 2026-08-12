import Foundation
import SlopadEditorBlockLayout
import SlopadCoreModel

let count = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 100_000
let index = BlockHeightIndexStorage()

let buildStart = ContinuousClock.now
for number in 0..<count {
    index.insert(
        blockID: BlockID("block-\(number)"),
        height: Double((number % 9) + 12),
        at: number
    )
}
let buildDuration = buildStart.duration(to: ContinuousClock.now)

#if SLOPAD_TREE_METRICS
index.resetVisitCount()
#endif
let queryStart = ContinuousClock.now
var checksum = 0
for number in 0..<10_000 {
    let yOffset = Double(number * 37).truncatingRemainder(dividingBy: index.totalHeight)
    let blockID = index.blockID(atY: yOffset)
    checksum &+= blockID.flatMap { index.index(of: $0) } ?? 0
}
let queryDuration = queryStart.duration(to: ContinuousClock.now)
#if SLOPAD_TREE_METRICS
let queryVisits = index.visitCount
#endif

#if SLOPAD_TREE_METRICS
index.resetVisitCount()
#endif
let updateStart = ContinuousClock.now
for number in 0..<10_000 {
    index.updateHeight(
        blockID: BlockID("block-\((number * 7919) % count)"),
        height: Double((number % 11) + 10)
    )
}
let updateDuration = updateStart.duration(to: ContinuousClock.now)
#if SLOPAD_TREE_METRICS
let updateVisits = index.visitCount
#endif

print("SlopadHeightBenchmark")
print("blocks=\(count)")
print("build=\(buildDuration)")
#if SLOPAD_TREE_METRICS
print("queries=10000 duration=\(queryDuration) visits=\(queryVisits) checksum=\(checksum)")
print("updates=10000 duration=\(updateDuration) visits=\(updateVisits)")
#else
print("queries=10000 duration=\(queryDuration) checksum=\(checksum)")
print("updates=10000 duration=\(updateDuration)")
#endif
