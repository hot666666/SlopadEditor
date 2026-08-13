import AppKit

// MARK: - AppKitEditorCanvasHandler

@MainActor
protocol AppKitEditorCanvasHandler: AnyObject {
    func drawCanvas(_ dirtyRect: NSRect)
    func handleMouseDown(documentPoint: CGPoint, clickCount: Int)
    func handleMouseDragged(documentPoint: CGPoint)
    func handleMouseUp(documentPoint: CGPoint)
    func handleNativeCommand(_ commandSelector: Selector) -> Bool
    func insertTextFromNativeSurface(_ text: String, replacementRange: NSRange)
    func setMarkedTextFromNativeSurface(
        _ text: String,
        selectedRange: NSRange,
        replacementRange: NSRange
    )
    func unmarkTextFromNativeSurface()
    func nativeSelectedRange() -> NSRange
    func nativeMarkedRange() -> NSRange
    func hasMarkedTextForNativeSurface() -> Bool
    func attributedSubstringForNativeSurface(range: NSRange) -> NSAttributedString?
    func firstRectForNativeSurface(range: NSRange) -> NSRect
    func canvasFocusDidChange(_ isFocused: Bool)
}

// MARK: - AppKitEditorCanvasView

@MainActor
final class AppKitEditorCanvasView: NSView, @preconcurrency NSTextInputClient {
    // MARK: - Private Types

    private enum Accessibility {
        static let canvasIdentifier = "AppKitEditorCanvas"
    }

    private enum UX {
        static let caretMinimumWidth: CGFloat = 1
        static let caretMinimumHeight: CGFloat = 14
    }

    // MARK: - State

    private weak var handler: (any AppKitEditorCanvasHandler)?
    #if DEBUG
        private let nativeInputTraceHandler: AppKitNativeInputTraceHandler?
    #endif
    private let textInsertionIndicator = NSTextInsertionIndicator()
    private var hasKeyboardFocus = false
    private var hasInsertionPoint = false

    package var insertionIndicatorDisplayMode: NSTextInsertionIndicator.DisplayMode {
        textInsertionIndicator.displayMode
    }

    package var insertionIndicatorFrame: NSRect {
        textInsertionIndicator.frame
    }

    // MARK: - Init

    #if DEBUG
        init(
            handler: (any AppKitEditorCanvasHandler)? = nil,
            frame: NSRect = NSRect(x: 0, y: 0, width: 860, height: 900),
            nativeInputTraceHandler: AppKitNativeInputTraceHandler? = nil
        ) {
            self.handler = handler
            self.nativeInputTraceHandler = nativeInputTraceHandler
            super.init(frame: frame)
            setupView()
        }
    #else
        init(
            handler: (any AppKitEditorCanvasHandler)? = nil,
            frame: NSRect = NSRect(x: 0, y: 0, width: 860, height: 900)
        ) {
            self.handler = handler
            super.init(frame: frame)
            setupView()
        }
    #endif

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - NSView

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            hasKeyboardFocus = false
            textInsertionIndicator.displayMode = .hidden
        }
        super.viewWillMove(toWindow: newWindow)
    }

    // Responder transitions are the only place a focus change is observable regardless of
    // who caused it — the host calling `setFocused`, a click landing on the canvas, or
    // another view in the window taking focus away. Reporting only host-initiated changes
    // would make a `@FocusState` binding work in one direction and silently desynchronize
    // in the other.
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            hasKeyboardFocus = true
            updateInsertionIndicatorDisplayMode()
            handler?.canvasFocusDidChange(true)
        }
        #if DEBUG
            trace(
                AppKitNativeInputTraceEvent(
                    category: .focus,
                    phase: .became,
                    outcome: accepted ? .accepted : .rejected,
                    canvasHasKeyboardFocus: hasKeyboardFocus,
                    inputContextAvailable: inputContext != nil,
                    inputSourceID: inputContext?.selectedKeyboardInputSource
                )
            )
        #endif
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            hasKeyboardFocus = false
            updateInsertionIndicatorDisplayMode()
            handler?.canvasFocusDidChange(false)
        }
        #if DEBUG
            trace(
                AppKitNativeInputTraceEvent(
                    category: .focus,
                    phase: .resigned,
                    outcome: resigned ? .accepted : .rejected,
                    canvasHasKeyboardFocus: hasKeyboardFocus,
                    inputContextAvailable: inputContext != nil,
                    inputSourceID: inputContext?.selectedKeyboardInputSource
                )
            )
        #endif
        return resigned
    }

    override func draw(_ dirtyRect: NSRect) {
        handler?.drawCanvas(dirtyRect)
    }

    override func mouseDown(with event: NSEvent) {
        handler?.handleMouseDown(
            documentPoint: convert(event.locationInWindow, from: nil),
            clickCount: event.clickCount
        )
    }

    override func mouseDragged(with event: NSEvent) {
        handler?.handleMouseDragged(documentPoint: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        handler?.handleMouseUp(documentPoint: convert(event.locationInWindow, from: nil))
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        #if DEBUG
            trace(
                AppKitNativeInputTraceEvent(
                    category: .keyDown,
                    phase: .received,
                    text: event.characters.map(AppKitNativeInputTraceText.init),
                    canvasIsFirstResponder: window?.firstResponder === self,
                    inputContextAvailable: inputContext != nil,
                    inputSourceID: inputContext?.selectedKeyboardInputSource
                )
            )
        #endif
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let actionModifiers = modifiers.intersection([.command, .control, .option, .shift])
        if let commandSelector = AppKitKeyboardCommandMapper.commandSelector(
            for: event,
            modifiers: actionModifiers
        ) {
            let handled = handler?.handleNativeCommand(commandSelector)
            #if DEBUG
                traceKeyDownRoute(
                    .nativeCommand,
                    selector: commandSelector,
                    handled: handled
                )
            #endif
            return
        }

        if AppKitKeyboardCommandMapper.isReturnKey(event), modifiers.contains(.shift) {
            let handled = handler?.handleNativeCommand(AppKitCommandSelectors.insertLineBreak)
            #if DEBUG
                traceKeyDownRoute(
                    .shiftReturnCommand,
                    selector: AppKitCommandSelectors.insertLineBreak,
                    handled: handled
                )
            #endif
            return
        }

        let tabSystemModifiers = modifiers.intersection([.command, .control, .option])
        if AppKitKeyboardCommandMapper.isTabKey(event), tabSystemModifiers.isEmpty {
            let commandSelector: Selector
            if modifiers.contains(.shift) {
                commandSelector = AppKitCommandSelectors.insertBacktab
            } else {
                commandSelector = AppKitCommandSelectors.insertTab
            }
            let handled = handler?.handleNativeCommand(commandSelector)
            #if DEBUG
                traceKeyDownRoute(
                    .tabCommand,
                    selector: commandSelector,
                    handled: handled
                )
            #endif
            return
        }

        #if DEBUG
            traceKeyDownRoute(.interpretKeyEvents, selector: nil, handled: nil)
            trace(
                AppKitNativeInputTraceEvent(
                    category: .interpretKeyEvents,
                    phase: .before,
                    canvasIsFirstResponder: window?.firstResponder === self,
                    inputContextAvailable: inputContext != nil,
                    inputSourceID: inputContext?.selectedKeyboardInputSource
                )
            )
        #endif
        interpretKeyEvents([event])
        #if DEBUG
            trace(
                AppKitNativeInputTraceEvent(
                    category: .interpretKeyEvents,
                    phase: .after,
                    canvasIsFirstResponder: window?.firstResponder === self,
                    inputContextAvailable: inputContext != nil,
                    inputSourceID: inputContext?.selectedKeyboardInputSource
                )
            )
        #endif
    }

    override func doCommand(by selector: Selector) {
        if handler?.handleNativeCommand(selector) == true {
            return
        }
        super.doCommand(by: selector)
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let text = Self.plainText(from: string) else {
            #if DEBUG
                traceTextCallback(
                    .insertText,
                    outcome: .rejected,
                    reason: .unsupportedTextPayload,
                    selectedRange: nil,
                    replacementRange: replacementRange,
                    text: nil
                )
            #endif
            return
        }
        #if DEBUG
            traceTextCallback(
                .insertText,
                outcome: .accepted,
                reason: .forwarded,
                selectedRange: nil,
                replacementRange: replacementRange,
                text: text
            )
        #endif
        handler?.insertTextFromNativeSurface(text, replacementRange: replacementRange)
    }

    func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        guard let text = Self.plainText(from: string) else {
            #if DEBUG
                traceTextCallback(
                    .setMarkedText,
                    outcome: .rejected,
                    reason: .unsupportedTextPayload,
                    selectedRange: selectedRange,
                    replacementRange: replacementRange,
                    text: nil
                )
            #endif
            return
        }
        #if DEBUG
            traceTextCallback(
                .setMarkedText,
                outcome: .accepted,
                reason: .forwarded,
                selectedRange: selectedRange,
                replacementRange: replacementRange,
                text: text
            )
        #endif
        handler?.setMarkedTextFromNativeSurface(
            text,
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
    }

    func unmarkText() {
        #if DEBUG
            traceTextCallback(
                .unmarkText,
                outcome: .accepted,
                reason: .forwarded,
                selectedRange: nil,
                replacementRange: nil,
                text: nil
            )
        #endif
        handler?.unmarkTextFromNativeSurface()
    }

    func selectedRange() -> NSRange {
        handler?.nativeSelectedRange() ?? NSRange(location: 0, length: 0)
    }

    func markedRange() -> NSRange {
        handler?.nativeMarkedRange() ?? NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        handler?.hasMarkedTextForNativeSurface() ?? false
    }

    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        actualRange?.pointee = range
        return handler?.attributedSubstringForNativeSurface(range: range)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.foregroundColor, .backgroundColor, .underlineStyle]
    }

    func firstRect(
        forCharacterRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSRect {
        actualRange?.pointee = range
        return handler?.firstRectForNativeSurface(range: range) ?? .zero
    }

    func characterIndex(for point: NSPoint) -> Int {
        selectedRange().location
    }

    // MARK: - Helpers

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setAccessibilityIdentifier(Accessibility.canvasIdentifier)
        textInsertionIndicator.displayMode = .hidden
        addSubview(textInsertionIndicator)
    }

    func updateInsertionPoint(_ caretRect: NSRect?) {
        hasInsertionPoint = caretRect != nil
        if let caretRect {
            textInsertionIndicator.frame = NSRect(
                x: caretRect.minX,
                y: caretRect.minY,
                width: max(UX.caretMinimumWidth, caretRect.width),
                height: max(UX.caretMinimumHeight, caretRect.height)
            )
        }
        updateInsertionIndicatorDisplayMode()
    }

    private func updateInsertionIndicatorDisplayMode() {
        textInsertionIndicator.displayMode = hasKeyboardFocus && hasInsertionPoint
            ? .automatic
            : .hidden
    }

    private static func plainText(from string: Any) -> String? {
        if let string = string as? String {
            return string
        }
        if let attributedString = string as? NSAttributedString {
            return attributedString.string
        }
        return nil
    }

    #if DEBUG
        private func trace(_ event: @autoclosure () -> AppKitNativeInputTraceEvent) {
            guard let nativeInputTraceHandler else { return }
            nativeInputTraceHandler(event())
        }

        private func traceKeyDownRoute(
            _ route: AppKitNativeInputTraceEvent.Route,
            selector: Selector?,
            handled: Bool?
        ) {
            trace(
                AppKitNativeInputTraceEvent(
                    category: .keyDown,
                    phase: .routed,
                    route: route,
                    outcome: handled.map { $0 ? .handled : .refused },
                    selector: selector.map(NSStringFromSelector),
                    canvasIsFirstResponder: window?.firstResponder === self,
                    inputContextAvailable: inputContext != nil,
                    inputSourceID: inputContext?.selectedKeyboardInputSource
                )
            )
        }

        private func traceTextCallback(
            _ callback: AppKitNativeInputTraceEvent.Callback,
            outcome: AppKitNativeInputTraceEvent.Outcome,
            reason: AppKitNativeInputTraceEvent.Reason,
            selectedRange: NSRange?,
            replacementRange: NSRange?,
            text: String?
        ) {
            trace(
                AppKitNativeInputTraceEvent(
                    category: .textCallback,
                    phase: .received,
                    callback: callback,
                    outcome: outcome,
                    reason: reason,
                    text: text.map(AppKitNativeInputTraceText.init),
                    selectedRange: selectedRange.map(AppKitNativeInputTraceRange.init),
                    replacementRange: replacementRange.map(AppKitNativeInputTraceRange.init),
                    canvasIsFirstResponder: window?.firstResponder === self,
                    inputContextAvailable: inputContext != nil,
                    inputSourceID: inputContext?.selectedKeyboardInputSource
                )
            )
        }
    #endif
}
