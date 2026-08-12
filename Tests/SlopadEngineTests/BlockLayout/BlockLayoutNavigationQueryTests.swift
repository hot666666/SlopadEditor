import Testing

@testable import SlopadEditorBlockLayout
import SlopadCoreModel

@Suite("BlockLayout 이동 조회")
struct BlockLayoutNavigationQueryTests {
    @Test("상대 block ID 조회는 visible order 안에서 offset만큼 떨어진 block을 반환한다")
    func relativeBlockIDResolvesNeighborInVisibleOrder() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let c: BlockID = "c"
        let document = makeFlatDocument([Block(id: a), Block(id: b), Block(id: c)])
        let blockLayout = BlockLayout()

        // When
        let previous = blockLayout.visibleBlockID(relativeTo: b, by: -1, document: document)
        let next = blockLayout.visibleBlockID(relativeTo: b, by: 1, document: document)

        // Then
        #expect(previous == a)
        #expect(next == c)
    }

    @Test("상대 block ID 조회가 visible order 밖으로 나가면 nil을 반환한다")
    func relativeBlockIDRejectsOutOfBoundsOffset() {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let document = makeFlatDocument([Block(id: a), Block(id: b)])
        let blockLayout = BlockLayout()

        // When
        let previous = blockLayout.visibleBlockID(relativeTo: a, by: -1, document: document)
        let missing = blockLayout.visibleBlockID(relativeTo: "missing", by: 1, document: document)

        // Then
        #expect(previous == nil)
        #expect(missing == nil)
    }
}
