import SlopadCoreModel

// MARK: - TextKitBlockChromeMetrics

struct TextKitBlockChromeMetrics {
    let topPadding: Double
    let bottomPadding: Double

    var verticalPadding: Double {
        topPadding + bottomPadding
    }

    static func metrics(for kind: BlockKind) -> TextKitBlockChromeMetrics {
        switch kind {
        case .divider:
            return TextKitBlockChromeMetrics(topPadding: 4, bottomPadding: 4)
        case .codeBlock:
            return TextKitBlockChromeMetrics(topPadding: 9, bottomPadding: 9)
        default:
            return TextKitBlockChromeMetrics(topPadding: 5, bottomPadding: 5)
        }
    }
}
