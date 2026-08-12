import AppKit
import SlopadEditorEngine

// MARK: - Floating Formatting Toolbar

@MainActor
package final class AppKitFloatingFormattingToolbar: NSVisualEffectView {
    package enum Item: String, CaseIterable, Sendable {
        case strong
        case emphasis
        case code
        case strikethrough
        case clear
    }

    package enum Placement: Sendable {
        case above
        case below
    }

    package struct ItemState {
        package let isEnabled: Bool
        package let value: NSControl.StateValue
        package let commitsComposition: Bool
    }

    private enum UX {
        static let size = NSSize(width: 224, height: 40)
        static let contentInset: CGFloat = 5
        static let gap: CGFloat = 8
        static let containerInset: CGFloat = 8
        static let cornerRadius: CGFloat = 9
        static let animationDuration: TimeInterval = 0.12
    }

    var onActionRequested: ((EditorCommandAction) -> Void)?

    private let stackView = NSStackView()
    private var buttons: [Item: AppKitFormattingButton] = [:]
    private(set) var placement: Placement = .above

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: frameRect.origin, size: UX.size))
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func synchronize(
        commandState: EditorCommandState,
        presentation: EditorSelectionPresentation,
        anchorInContainer: CGRect?,
        containerBounds: CGRect
    ) {
        let shouldPresent =
            commandState.detail == .rich
            && (commandState.selectionMode == .text || commandState.selectionMode == .blocks)
            && presentation.visibleBounds != nil
            && anchorInContainer != nil
        guard shouldPresent, let anchorInContainer else {
            setPresented(false, targetFrame: frame)
            return
        }

        synchronizeButtons(commandState)
        let placementResult = Self.placementFrame(
            anchor: anchorInContainer,
            toolbarSize: UX.size,
            containerBounds: containerBounds
        )
        placement = placementResult.placement
        setPresented(true, targetFrame: placementResult.frame)
    }

    package func itemState(_ item: Item) -> ItemState? {
        buttons[item].map {
            ItemState(
                isEnabled: $0.isEnabled,
                value: $0.state,
                commitsComposition: $0.commitsComposition
            )
        }
    }

    package func perform(_ item: Item) {
        buttons[item]?.performClick(nil)
    }

    package static func placementFrame(
        anchor: CGRect,
        toolbarSize: NSSize,
        containerBounds: CGRect
    ) -> (frame: CGRect, placement: Placement) {
        let safeBounds = containerBounds.insetBy(dx: UX.containerInset, dy: UX.containerInset)
        let fitsAbove = anchor.maxY + UX.gap + toolbarSize.height <= safeBounds.maxY
        let preferredPlacement: Placement = fitsAbove ? .above : .below
        let preferredY =
            fitsAbove
            ? anchor.maxY + UX.gap
            : anchor.minY - UX.gap - toolbarSize.height
        let maximumX = max(safeBounds.minX, safeBounds.maxX - toolbarSize.width)
        let maximumY = max(safeBounds.minY, safeBounds.maxY - toolbarSize.height)
        let frame = CGRect(
            x: min(max(anchor.midX - toolbarSize.width / 2, safeBounds.minX), maximumX),
            y: min(max(preferredY, safeBounds.minY), maximumY),
            width: toolbarSize.width,
            height: toolbarSize.height
        )
        return (frame, preferredPlacement)
    }

    private func setupView() {
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = UX.cornerRadius
        layer?.masksToBounds = true
        isHidden = true
        alphaValue = 0

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 4
        stackView.frame = bounds.insetBy(dx: UX.contentInset, dy: UX.contentInset)
        stackView.autoresizingMask = [.width, .height]
        addSubview(stackView)

        for item in Item.allCases {
            let button = makeButton(item)
            buttons[item] = button
            stackView.addArrangedSubview(button)
        }
    }

    private func makeButton(_ item: Item) -> AppKitFormattingButton {
        let button = AppKitFormattingButton(title: title(for: item), target: self, action: nil)
        button.identifier = NSUserInterfaceItemIdentifier(item.rawValue)
        button.bezelStyle = .texturedRounded
        button.font = font(for: item)
        button.toolTip = toolTip(for: item)
        button.setButtonType(item == .clear ? .momentaryPushIn : .toggle)
        button.allowsMixedState = item != .clear
        button.target = self
        button.action = #selector(buttonPressed(_:))
        return button
    }

    private func title(for item: Item) -> String {
        switch item {
        case .strong: "B"
        case .emphasis: "I"
        case .code: "<>"
        case .strikethrough: "S"
        case .clear: "Clear"
        }
    }

    private func font(for item: Item) -> NSFont {
        switch item {
        case .strong:
            return .systemFont(ofSize: 13, weight: .bold)
        case .emphasis:
            return NSFontManager.shared.convert(
                .systemFont(ofSize: 13),
                toHaveTrait: .italicFontMask
            )
        case .strikethrough:
            return .systemFont(ofSize: 13, weight: .medium)
        case .code:
            return .monospacedSystemFont(ofSize: 11, weight: .medium)
        case .clear:
            return .systemFont(ofSize: 11, weight: .regular)
        }
    }

    private func toolTip(for item: Item) -> String {
        switch item {
        case .strong: "Bold"
        case .emphasis: "Italic"
        case .code: "Inline code"
        case .strikethrough: "Strikethrough"
        case .clear: "Clear inline formatting"
        }
    }

    private func synchronizeButtons(_ state: EditorCommandState) {
        synchronizeToggle(.strong, kind: .strong, state: state)
        synchronizeToggle(.emphasis, kind: .emphasis, state: state)
        synchronizeToggle(.code, kind: .code, state: state)
        synchronizeToggle(.strikethrough, kind: .strikethrough, state: state)
        synchronize(
            .clear,
            toggleState: .off,
            availability: state.clearInlineStylesAvailability
        )
    }

    private func synchronizeToggle(
        _ item: Item,
        kind: BlockContent.InlineMark.Kind,
        state: EditorCommandState
    ) {
        synchronize(
            item,
            toggleState: state.toggleState(for: kind),
            availability: state.availability(for: .toggleInlineStyle(kind))
        )
    }

    private func synchronize(
        _ item: Item,
        toggleState: EditorToggleState,
        availability: EditorActionAvailability
    ) {
        guard let button = buttons[item] else { return }
        button.isEnabled = availability != .unavailable && toggleState != .unavailable
        switch toggleState {
        case .unavailable, .off:
            button.state = .off
        case .on:
            button.state = .on
        case .mixed:
            button.state = .mixed
        }
        button.commitsComposition = availability == .availableAfterCompositionCommit
        button.contentTintColor = button.commitsComposition ? .systemOrange : .controlTextColor
        let baseToolTip = toolTip(for: item)
        button.toolTip =
            button.commitsComposition
            ? "\(baseToolTip) — commits active composition"
            : baseToolTip
    }

    private func setPresented(_ presented: Bool, targetFrame: CGRect) {
        if presented {
            let wasHidden = isHidden
            isHidden = false
            if wasHidden {
                frame = targetFrame
                alphaValue = 1
                return
            }
            if frame == targetFrame {
                layer?.removeAllAnimations()
                frame = targetFrame
                alphaValue = 1
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = UX.animationDuration
                animator().frame = targetFrame
            }
        } else if !isHidden {
            alphaValue = 0
            isHidden = true
        }
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        guard
            let rawValue = sender.identifier?.rawValue,
            let item = Item(rawValue: rawValue)
        else { return }
        switch item {
        case .strong:
            onActionRequested?(.toggleInlineStyle(.strong))
        case .emphasis:
            onActionRequested?(.toggleInlineStyle(.emphasis))
        case .code:
            onActionRequested?(.toggleInlineStyle(.code))
        case .strikethrough:
            onActionRequested?(.toggleInlineStyle(.strikethrough))
        case .clear:
            onActionRequested?(.clearInlineStyles)
        }
    }
}

@MainActor
private final class AppKitFormattingButton: NSButton {
    var commitsComposition = false

    override var acceptsFirstResponder: Bool {
        false
    }
}
