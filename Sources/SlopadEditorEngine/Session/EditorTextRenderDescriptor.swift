import SlopadCoreModel

// MARK: - EditorTextRenderDescriptor

public struct EditorTextRenderDescriptor: Sendable {
    public let measureRequest: BlockMeasureRequest
    public let frame: EditorRect

    init(measureRequest: BlockMeasureRequest, frame: EditorRect) {
        self.measureRequest = measureRequest
        self.frame = frame
    }
}
