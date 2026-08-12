import SlopadCoreModel

// MARK: - EditorBlockDragState

public struct EditorBlockDragState: Sendable {
    public let dropIndicator: EditorRect?

    init(dropIndicator: EditorRect? = nil) {
        self.dropIndicator = dropIndicator
    }
}

// MARK: - EditorBlockSelectionRectangleState

public struct EditorBlockSelectionRectangleState: Sendable {
    public let rect: EditorRect

    init(rect: EditorRect) {
        self.rect = rect
    }
}
