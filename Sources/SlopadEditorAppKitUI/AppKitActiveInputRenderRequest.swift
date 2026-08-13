// MARK: - AppKitActiveInputRenderRequest

struct AppKitActiveInputRenderRequest: Hashable, Sendable {
    var makeFirstResponder: Bool
    var preserveNativeSurface: Bool
    var scrollSelectionIntoView: Bool

    init(
        makeFirstResponder: Bool,
        preserveNativeSurface: Bool = false,
        scrollSelectionIntoView: Bool = false
    ) {
        self.makeFirstResponder = makeFirstResponder
        self.preserveNativeSurface = preserveNativeSurface
        self.scrollSelectionIntoView = scrollSelectionIntoView
    }
}
