import SlopadCoreModel

// MARK: - BlockLayoutGeometry

package struct BlockLayoutGeometry {
    package let blockID: BlockID
    let topY: Double
    let height: Double
    package let depth: Int
    package let markerKind: BlockMarkerKind

    package func frame(width: Double) -> EditorRect {
        EditorRect(x: 0, y: topY, width: width, height: height)
    }
}
