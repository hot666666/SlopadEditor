import AppKit
import SlopadEngine

// MARK: - AppKitSlashCommandOverlay

/// AppKit presentation for the fixed slash-command vocabulary.
///
/// It holds only ephemeral presentation state (frame and highlighted row). The command and
/// source revision remain Engine values, and selecting a row merely reports that identity to
/// the controller; it never owns document mutation semantics.
@MainActor
final class AppKitSlashCommandOverlay: NSView {
    private enum UX {
        static let width: CGFloat = 220
        static let rowHeight: CGFloat = 28
        static let verticalPadding: CGFloat = 6
        static let anchorGap: CGFloat = 5
    }

    private final class RowButton: NSButton {
        override var acceptsFirstResponder: Bool { false }
    }

    private var presentation: EditorSlashCommandPresentation?
    private var displayedCommands: [EditorSlashCommand] = []
    private var highlightedIndex = 0
    private var rowButtons: [RowButton] = []
    var onCommandRequested: ((EditorSlashCommand, EditorDocumentRevision) -> Void)?
    var onDismissRequested: (() -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.98).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.masksToBounds = true
        clipsToBounds = true
        setAccessibilityRole(.list)
        setAccessibilityLabel("Slash commands")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func synchronize(
        presentation: EditorSlashCommandPresentation?,
        anchorInContainer: NSRect?,
        containerBounds: NSRect
    ) {
        guard let presentation, let anchorInContainer else {
            dismiss()
            return
        }
        self.presentation = presentation
        if highlightedIndex >= presentation.commands.count {
            highlightedIndex = max(0, presentation.commands.count - 1)
        }
        let width = min(UX.width, max(0, containerBounds.width))
        let desiredHeight = CGFloat(max(1, presentation.commands.count)) * UX.rowHeight
            + 2 * UX.verticalPadding
        let height = min(desiredHeight, max(0, containerBounds.height))
        guard width > 0, height > 0 else {
            dismiss()
            return
        }

        rebuildRowsIfNeeded(commands: presentation.commands)
        let maximumX = containerBounds.maxX - width
        let preferredX = min(max(anchorInContainer.minX, containerBounds.minX), maximumX)
        let belowY = anchorInContainer.maxY + UX.anchorGap
        let unboundedY = belowY + height <= containerBounds.maxY
            ? belowY
            : anchorInContainer.minY - UX.anchorGap - height
        let preferredY = min(
            max(unboundedY, containerBounds.minY),
            containerBounds.maxY - height
        )
        frame = NSRect(x: preferredX, y: preferredY, width: width, height: height)
        layoutRows()
        isHidden = false
        updateRowAppearance()
    }

    @discardableResult
    func handleCommand(_ selector: Selector) -> Bool {
        guard !isHidden else { return false }
        switch selector {
        case AppKitCommandSelectors.moveUp:
            moveHighlight(by: -1)
        case AppKitCommandSelectors.moveDown:
            moveHighlight(by: 1)
        case AppKitCommandSelectors.insertNewline:
            requestHighlightedCommand()
        case AppKitCommandSelectors.cancelOperation:
            onDismissRequested?()
            dismiss()
        default:
            return false
        }
        return true
    }

    var isPresented: Bool { !isHidden }

    func dismiss() {
        presentation = nil
        displayedCommands = []
        highlightedIndex = 0
        isHidden = true
        rowButtons.forEach { $0.removeFromSuperview() }
        rowButtons = []
    }

    private func rebuildRowsIfNeeded(commands: [EditorSlashCommand]) {
        guard displayedCommands != commands else { return }
        rowButtons.forEach { $0.removeFromSuperview() }
        displayedCommands = commands
        rowButtons = commands.enumerated().map { index, command in
            let button = RowButton(title: command.title, target: self, action: #selector(selectRow(_:)))
            button.tag = index
            button.alignment = .left
            button.bezelStyle = .texturedRounded
            button.setAccessibilityIdentifier("AppKitSlashCommand.\(command.title)")
            button.setAccessibilityLabel(command.title)
            addSubview(button)
            return button
        }
        if commands.isEmpty {
            let button = RowButton(title: "No matching commands", target: nil, action: nil)
            button.isEnabled = false
            button.alignment = .left
            button.setAccessibilityLabel("No matching commands")
            addSubview(button)
            rowButtons = [button]
        }
    }

    private func layoutRows() {
        let width = bounds.width
        for (index, button) in rowButtons.enumerated() {
            button.frame = NSRect(
                x: 6,
                y: UX.verticalPadding + CGFloat(index) * UX.rowHeight,
                width: max(0, width - 12),
                height: UX.rowHeight
            )
        }
    }

    private func moveHighlight(by delta: Int) {
        guard let presentation, !presentation.commands.isEmpty else { return }
        highlightedIndex = (highlightedIndex + delta + presentation.commands.count)
            % presentation.commands.count
        updateRowAppearance()
    }

    private func updateRowAppearance() {
        for (index, button) in rowButtons.enumerated() {
            button.state = index == highlightedIndex ? .on : .off
            button.setAccessibilityValue(index == highlightedIndex ? "selected" : nil)
        }
    }

    @objc private func selectRow(_ sender: NSButton) {
        highlightedIndex = sender.tag
        requestHighlightedCommand()
    }

    private func requestHighlightedCommand() {
        guard
            let presentation,
            presentation.commands.indices.contains(highlightedIndex)
        else { return }
        let command = presentation.commands[highlightedIndex]
        onCommandRequested?(command, presentation.sourceRevision)
    }
}
