import SlopadCoreModel

// MARK: - EditorRenderedBlock

public struct EditorRenderedBlock: Sendable {
    public let markerKind: BlockMarkerKind
    public let frame: EditorRect
    public let textRender: EditorTextRenderDescriptor

    public var id: BlockID { textRender.measureRequest.blockID }
    public var kind: BlockKind { textRender.measureRequest.kind }
    public var depth: Int { textRender.measureRequest.depth }

    init(
        markerKind: BlockMarkerKind = .none,
        frame: EditorRect,
        textRender: EditorTextRenderDescriptor
    ) {
        self.markerKind = markerKind
        self.frame = frame
        self.textRender = textRender
    }
}
