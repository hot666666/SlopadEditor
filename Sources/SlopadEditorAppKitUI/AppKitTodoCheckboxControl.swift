import AppKit
import SlopadEditorEngine

// MARK: - Todo Checkbox Control

@MainActor
enum AppKitTodoCheckboxControl {
    private enum UX {
        static let size: CGFloat = 16
        static let topPadding: CGFloat = 9
        static let pressedOutset: CGFloat = 3
        static let symbolFraction: CGFloat = 0.9
        static let fallbackInset: CGFloat = 3
    }

    static func hitRect(blockFrame: CGRect, style: AppKitEditorStyle) -> CGRect {
        let gutterRect = CGRect(
            x: 0,
            y: blockFrame.minY,
            width: style.gutterWidth,
            height: blockFrame.height
        )
        return CGRect(
            x: gutterRect.midX - UX.size / 2,
            y: gutterRect.minY + UX.topPadding,
            width: UX.size,
            height: UX.size
        )
    }

    static func draw(
        isChecked: Bool,
        blockFrame: CGRect,
        style: AppKitEditorStyle,
        isPressed: Bool
    ) {
        let rect = hitRect(blockFrame: blockFrame, style: style)
        if isPressed {
            NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
            NSBezierPath(
                roundedRect: rect.insetBy(dx: -UX.pressedOutset, dy: -UX.pressedOutset),
                xRadius: 5,
                yRadius: 5
            ).fill()
        }

        let symbolName = isChecked ? "checkmark.square.fill" : "square"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let configuration = NSImage.SymbolConfiguration(
                paletteColors: [.controlAccentColor]
            )
            let configuredImage = image.withSymbolConfiguration(configuration) ?? image
            configuredImage.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: UX.symbolFraction
            )
        } else {
            let path = NSBezierPath(rect: rect.insetBy(dx: UX.fallbackInset, dy: UX.fallbackInset))
            path.lineWidth = 1.5
            path.stroke()
        }
    }
}
