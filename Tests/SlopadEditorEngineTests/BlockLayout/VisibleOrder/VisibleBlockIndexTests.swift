import Testing

@testable import SlopadEditorBlockLayout
import SlopadCoreModel

@Suite("visible block index projection 동작")
struct VisibleBlockIndexTests {
    @Test("문서 트리를 visible preorder 순서로 펼친다")
    func documentVisibleOrderReturnsPreorderEntries() {
        // Given
        let root: BlockID = "root"
        let child: BlockID = "child"
        let grandchild: BlockID = "grandchild"
        var document = Document.singleParagraph("root", id: root)
        document.appendChild(Block(id: child), to: root)
        document.appendChild(Block(id: grandchild), to: child)
        let expectedEntries = [
            VisibleBlock(blockID: root, depth: 0, parentID: nil),
            VisibleBlock(blockID: child, depth: 1, parentID: root),
            VisibleBlock(blockID: grandchild, depth: 2, parentID: child),
        ]

        // When
        let index = VisibleBlockIndex(document: document)

        // Then
        assertVisibleEntries(index.entriesSnapshot(), equal: expectedEntries)
        #expect(index.count == expectedEntries.count)
    }

    @Test("초기 항목을 index와 blockID로 조회한다")
    func indexesInitialEntries() {
        // Given
        let entries = [
            VisibleBlock(blockID: "a", depth: 0, parentID: nil),
            VisibleBlock(blockID: "b", depth: 1, parentID: "a"),
            VisibleBlock(blockID: "c", depth: 0, parentID: nil),
        ]
        let index = VisibleBlockIndex(entries, revision: 10)

        // When
        let indexedEntry = index.entry(at: 1)
        let blockEntry = index.entry(for: "b")
        let blockIndex = index.index(of: "b")
        let snapshotEntries = index.entriesSnapshot()

        // Then
        #expect(index.count == 3)
        assertVisibleEntry(indexedEntry, equal: entries[1])
        assertVisibleEntry(blockEntry, equal: entries[1])
        #expect(blockIndex == 1)
        assertVisibleEntries(snapshotEntries, equal: entries)
        #expect(index.revision == 10)
    }

    @Test("삽입 삭제 갱신이 순서와 revision을 바꾼다")
    func mutatesEntriesIncrementally() {
        // Given
        let index = VisibleBlockIndex(
            [
                VisibleBlock(blockID: "a", depth: 0, parentID: nil),
                VisibleBlock(blockID: "c", depth: 0, parentID: nil),
            ],
            revision: 1
        )
        let inserted = VisibleBlock(blockID: "b", depth: 1, parentID: "a")
        let updated = VisibleBlock(blockID: "b", depth: 0, parentID: nil)

        // When
        let didInsert = index.insert(inserted, at: 1)
        let didUpdate = index.update(updated)
        let removed = index.remove(blockID: "a")

        // Then
        #expect(didInsert)
        #expect(didUpdate)
        #expect(removed?.blockID == "a")
        assertVisibleEntries(index.entriesSnapshot(), equal: [
            updated,
            VisibleBlock(blockID: "c", depth: 0, parentID: nil),
        ])
        #expect(index.revision == 4)
    }

    @Test("subtree span을 root depth 기준으로 반환한다")
    func returnsSubtreeSpanEntries() {
        // Given
        let entries = [
            VisibleBlock(blockID: "a", depth: 0, parentID: nil),
            VisibleBlock(blockID: "b", depth: 1, parentID: "a"),
            VisibleBlock(blockID: "c", depth: 2, parentID: "b"),
            VisibleBlock(blockID: "d", depth: 0, parentID: nil),
        ]
        let index = VisibleBlockIndex(entries, revision: 1)

        // When
        let span = index.spanEntries(rootID: "b")

        // Then
        assertVisibleEntries(span, equal: Array(entries[1...2]))
    }

    @Test("중복 blockID span 삽입은 기존 index를 바꾸지 않는다")
    func duplicateBulkInsertDoesNotPartiallyMutateIndex() {
        // Given
        let entries = [
            VisibleBlock(blockID: "a", depth: 0, parentID: nil),
            VisibleBlock(blockID: "b", depth: 0, parentID: nil),
        ]
        let index = VisibleBlockIndex(entries, revision: 3)
        let duplicateSpan = [
            VisibleBlock(blockID: "c", depth: 0, parentID: nil),
            VisibleBlock(blockID: "b", depth: 0, parentID: nil),
        ]

        // When
        let inserted = index.insert(contentsOf: duplicateSpan, at: 1)

        // Then
        #expect(!inserted)
        assertVisibleEntries(index.entriesSnapshot(), equal: entries)
        #expect(index.revision == 3)
    }
}

private func assertVisibleEntries(
    _ actual: [VisibleBlock]?,
    equal expected: [VisibleBlock]
) {
    guard let actual else {
        #expect(Bool(false))
        return
    }
    #expect(actual.count == expected.count)
    for (actualEntry, expectedEntry) in zip(actual, expected) {
        assertVisibleEntry(actualEntry, equal: expectedEntry)
    }
}

private func assertVisibleEntry(
    _ actual: VisibleBlock?,
    equal expected: VisibleBlock
) {
    guard let actual else {
        #expect(Bool(false))
        return
    }
    #expect(actual.blockID == expected.blockID)
    #expect(actual.depth == expected.depth)
    #expect(actual.parentID == expected.parentID)
}
