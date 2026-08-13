import AppKit
import SlopadEditorEngine

@MainActor
struct AppKitEditorAccessibilityProjection {
    typealias NotificationPoster = (Any, NSAccessibility.Notification) -> Void

    private let postNotification: NotificationPoster

    init(
        postNotification: @escaping NotificationPoster = { element, notification in
            NSAccessibility.post(element: element, notification: notification)
        }
    ) {
        self.postNotification = postNotification
    }

    func synchronize(blocks: [EditorBlockInput], on scrollView: NSScrollView) {
        let value = blocks
            .map(\.content.text)
            .joined(separator: "\n")
        if scrollView.accessibilityValue() as? String != value {
            scrollView.setAccessibilityValue(value)
            postNotification(scrollView, .valueChanged)
        }

        let blockStructure = blocks
            .map { accessibilityName(for: $0.kind) }
            .joined(separator: ", ")
        if scrollView.accessibilityTitle() != blockStructure {
            scrollView.setAccessibilityTitle(blockStructure)
            postNotification(scrollView, .titleChanged)
        }
    }

    private func accessibilityName(for kind: BlockKind) -> String {
        switch kind {
        case .paragraph:
            "Paragraph"
        case .heading(let level):
            "Heading \(level.rawValue)"
        case .unorderedListItem:
            "Unordered List Item"
        case .orderedListItem(let restartNumber):
            if let restartNumber {
                "Ordered List Item \(restartNumber)"
            } else {
                "Ordered List Item"
            }
        case .quote:
            "Quote"
        case .codeBlock(let language):
            if let language, !language.isEmpty {
                "Code Block \(language)"
            } else {
                "Code Block"
            }
        case .divider:
            "Divider"
        case .todo(let isChecked):
            isChecked ? "Todo Checked" : "Todo Unchecked"
        }
    }
}
