import SlopadCoreModel

// MARK: - EditorNavigationDirection

enum EditorNavigationDirection {
    case up
    case down
    case left
    case right

    var verticalStep: Int? {
        switch self {
        case .up:
            return -1
        case .down:
            return 1
        case .left, .right:
            return nil
        }
    }

    var horizontalStep: Int? {
        switch self {
        case .left:
            return -1
        case .right:
            return 1
        case .up, .down:
            return nil
        }
    }

    var textNavigationDirection: TextNavigationDirection? {
        switch self {
        case .left:
            return .left
        case .right:
            return .right
        case .up, .down:
            return nil
        }
    }
}
