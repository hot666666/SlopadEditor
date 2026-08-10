import AppKit
import SlopadEngine

// MARK: - AppKitActiveInputOwner

@MainActor
protocol AppKitActiveInputOwner: AnyObject {
    func documentTextForNativeInput(blockID: BlockID) -> String?
    func selectedPlainTextForClipboard() -> String?
    func clipboardWritePlan() -> EditorClipboardWritePlan?
    @discardableResult
    func handleNativeInputEvent(_ inputEvent: EditorInputEvent) -> EditorUpdate?
    func handleActiveInputRenderRequest(_ request: AppKitActiveInputRenderRequest)
    func currentViewport() -> EditorViewport
    func reportUnhandledAction(_ action: AppKitEditorAction, defaultHandled: Bool) -> Bool
}

extension AppKitActiveInputOwner {
    func clipboardWritePlan() -> EditorClipboardWritePlan? { nil }
}

enum AppKitClipboardContract {
    static let structuredType = NSPasteboard.PasteboardType(
        "com.hot666666.slopad.clipboard.v1"
    )
    static let maximumStructuredBytes = 8 * 1_024 * 1_024
}

@MainActor
protocol AppKitPasteboardAccess: AnyObject {
    @discardableResult func clearContents() -> Int
    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
    func data(forType dataType: NSPasteboard.PasteboardType) -> Data?
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
}

extension NSPasteboard: AppKitPasteboardAccess {}

// MARK: - AppKitActiveInputController

@MainActor
final class AppKitActiveInputController {
    // MARK: - Private Types

    @MainActor
    private final class SyncGuard {
        private var syncDepth = 0

        var shouldForwardNativeCallback: Bool {
            syncDepth == 0
        }

        #if DEBUG
            var currentDepth: Int {
                syncDepth
            }
        #endif

        func performSessionSync<T>(_ body: () throws -> T) rethrows -> T {
            syncDepth += 1
            defer { syncDepth -= 1 }
            return try body()
        }
    }

    private enum TextBoundaryDirection {
        case start
        case end
    }

    private enum BlockIndentDirection {
        case indent
        case outdent
    }

    // MARK: - Dependencies

    private weak var owner: (any AppKitActiveInputOwner)?
    private let pasteboard: any AppKitPasteboardAccess
    private let syncGuard = SyncGuard()
    #if DEBUG
        private let nativeInputTraceHandler: AppKitNativeInputTraceHandler?
    #endif

    // MARK: - State

    private var activeTextHostBlockID: BlockID?
    private var text = ""
    private var selectedRange = NSRange(location: 0, length: 0)
    private var sessionSelectedRange: SlopadEngine.TextRange?
    private var markedRange: NSRange?
    private var markedReplacementRange: NSRange?
    private var markedDocumentText: String?

    // MARK: - Init

    #if DEBUG
        init(
            owner: any AppKitActiveInputOwner,
            pasteboard: any AppKitPasteboardAccess = NSPasteboard.general,
            nativeInputTraceHandler: AppKitNativeInputTraceHandler? = nil
        ) {
            self.owner = owner
            self.pasteboard = pasteboard
            self.nativeInputTraceHandler = nativeInputTraceHandler
        }
    #else
        init(
            owner: any AppKitActiveInputOwner,
            pasteboard: any AppKitPasteboardAccess = NSPasteboard.general
        ) {
            self.owner = owner
            self.pasteboard = pasteboard
        }
    #endif

    // MARK: - State Access

    var activeText: String {
        text
    }

    var activeBlockID: BlockID? {
        activeTextHostBlockID
    }

    var activeSelectedRange: NSRange {
        selectedRange
    }

    var activeMarkedRange: NSRange {
        markedRange ?? NSRange(location: NSNotFound, length: 0)
    }

    var hasMarkedText: Bool {
        markedRange != nil
    }

    // MARK: - Session Sync

    func sync(activeTextInput: EditorSessionActiveTextInputDescriptor?) {
        let nextTextHostBlockID = activeTextInput?.renderDescriptor.measureRequest.blockID
        #if DEBUG
            trace(
                AppKitNativeInputTraceEvent(
                    category: .nativeSurfaceSync,
                    phase: .before,
                    blockToken: AppKitNativeInputTraceBlockToken.make(nextTextHostBlockID),
                    syncDepth: syncGuard.currentDepth,
                    characterCoordinatesInvalidated: false
                )
            )
        #endif
        activeTextHostBlockID = nil
        syncGuard.performSessionSync {
            #if DEBUG
                trace(
                    AppKitNativeInputTraceEvent(
                        category: .nativeSurfaceSync,
                        phase: .during,
                        blockToken: AppKitNativeInputTraceBlockToken.make(nextTextHostBlockID),
                        syncDepth: syncGuard.currentDepth,
                        characterCoordinatesInvalidated: false
                    )
                )
            #endif
            if let activeTextInput {
                let request = activeTextInput.renderDescriptor.measureRequest
                text = request.text
                selectedRange = activeTextInput.selectedRange.textKitNSRange(in: request.text)
                sessionSelectedRange = activeTextInput.selectedRange
            } else {
                text = ""
                selectedRange = NSRange(location: 0, length: 0)
                sessionSelectedRange = nil
            }
            markedRange = nil
            markedReplacementRange = nil
            markedDocumentText = nil
        }
        activeTextHostBlockID = nextTextHostBlockID
        #if DEBUG
            trace(
                AppKitNativeInputTraceEvent(
                    category: .nativeSurfaceSync,
                    phase: .after,
                    blockToken: AppKitNativeInputTraceBlockToken.make(activeTextHostBlockID),
                    syncDepth: syncGuard.currentDepth,
                    characterCoordinatesInvalidated: false
                )
            )
        #endif
    }

    func hide() {
        activeTextHostBlockID = nil
        text = ""
        selectedRange = NSRange(location: 0, length: 0)
        sessionSelectedRange = nil
        markedRange = nil
        markedReplacementRange = nil
        markedDocumentText = nil
    }

    // MARK: - Native Text Input

    func insertText(_ insertedText: String, replacementRange: NSRange) {
        #if DEBUG
            traceGuardOutcome(for: .insertText)
        #endif
        guard syncGuard.shouldForwardNativeCallback, let activeTextHostBlockID else { return }
        let documentText =
            markedDocumentText
            ?? owner?.documentTextForNativeInput(blockID: activeTextHostBlockID)
            ?? text
        let replacementRange =
            replacementRange.location == NSNotFound
            ? (markedReplacementRange ?? selectedRange)
            : replacementRange
        clearComposition()

        applyNativeReplacement(
            insertedText,
            replacementRange: replacementRange,
            blockID: activeTextHostBlockID,
            documentText: documentText
        )
    }

    func setMarkedText(
        _ markedText: String,
        selectedRange markedSelectedRange: NSRange,
        replacementRange: NSRange
    ) {
        #if DEBUG
            traceGuardOutcome(for: .setMarkedText)
        #endif
        guard syncGuard.shouldForwardNativeCallback, let activeTextHostBlockID else { return }
        let isBeginningComposition = markedRange == nil
        let documentText =
            markedDocumentText
            ?? owner?.documentTextForNativeInput(blockID: activeTextHostBlockID)
            ?? text
        let replacementRange = normalizedReplacementRange(
            replacementRange.location == NSNotFound
                ? (markedReplacementRange ?? selectedRange)
                : replacementRange,
            in: documentText
        )
        let replacementTextRange =
            replacementRange.slopadTextRange(in: documentText)
            ?? SlopadEngine.TextRange.point(documentText.count)
        let markedSelectedRange = normalizedMarkedSelectionRange(
            markedSelectedRange,
            in: markedText
        )

        text = replacingText(documentText, in: replacementRange, with: markedText)
        markedRange = NSRange(location: replacementRange.location, length: markedText.utf16.count)
        markedReplacementRange = replacementRange
        markedDocumentText = documentText
        selectedRange = NSRange(
            location: replacementRange.location + markedSelectedRange.location,
            length: markedSelectedRange.length
        )
        sessionSelectedRange = nil

        let compositionEvent: EditorInputEvent =
            isBeginningComposition
            ? .beginComposition(
                blockID: activeTextHostBlockID,
                replacementRange: replacementTextRange,
                text: markedText
            )
            : .updateComposition(
                blockID: activeTextHostBlockID,
                replacementRange: replacementTextRange,
                text: markedText
            )
        emitEditorEvent(compositionEvent)
        if let effectiveSelectedRange = selectedRange.slopadTextRange(in: text) {
            let update = emitEditorEvent(
                .activeTextSelectionChanged(
                    blockID: activeTextHostBlockID,
                    selectedRange: effectiveSelectedRange
                )
            )
            if update != nil {
                sessionSelectedRange = effectiveSelectedRange
            }
        }
        requestRender(makeFirstResponder: true, preserveNativeSurface: true)
    }

    func unmarkText() {
        #if DEBUG
            trace(
                AppKitNativeInputTraceEvent(
                    category: .activeInputGuard,
                    phase: .result,
                    callback: .unmarkText,
                    outcome: .accepted,
                    reason: .callbackHasNoSyncGuard,
                    blockToken: AppKitNativeInputTraceBlockToken.make(activeTextHostBlockID),
                    syncDepth: syncGuard.currentDepth
                )
            )
        #endif
        markedRange = nil
        markedReplacementRange = nil
        markedDocumentText = nil
        sessionSelectedRange = nil
        emitEditorEvent(.commitComposition)
        syncSelectionFromNativeSurface()
        requestRender(
            makeFirstResponder: true,
            preserveNativeSurface: false
        )
    }

    func replaceText(
        _ newText: String,
        blockID: BlockID,
        preservingNativeSelection: Bool = false
    ) {
        let preservedRange =
            preservingNativeSelection
            ? selectedRange.slopadTextRange(in: newText)
            : nil
        let documentText = owner?.documentTextForNativeInput(blockID: blockID) ?? text
        let replacementRange = NSRange(location: 0, length: documentText.utf16.count)
        let replacementTextRange =
            replacementRange.slopadTextRange(in: documentText)
            ?? SlopadEngine.TextRange(0, documentText.count)
        syncGuard.performSessionSync {
            self.text = newText
            self.selectedRange = NSRange(location: newText.utf16.count, length: 0)
            self.sessionSelectedRange = nil
            self.markedRange = nil
            self.markedReplacementRange = nil
            self.markedDocumentText = nil
        }
        emitEditorEvent(
            .command(
                .replaceText(
                    blockID: blockID,
                    range: replacementTextRange,
                    text: newText
                )
            )
        )

        if let preservedRange {
            emitEditorEvent(
                .activeTextSelectionChanged(
                    blockID: blockID,
                    selectedRange: preservedRange
                )
            )
        }
        requestRender(makeFirstResponder: true, scrollSelectionIntoView: true)
    }

    // MARK: - Commands

    func handleCommand(_ commandSelector: Selector) -> Bool {
        if activeTextHostBlockID != nil {
            syncSelectionFromNativeSurface()
        }

        switch commandSelector {
        case AppKitCommandSelectors.insertNewline:
            return handleSemanticAction(.enter)

        case AppKitCommandSelectors.insertLineBreak,
            AppKitCommandSelectors.insertNewlineIgnoringFieldEditor:
            return handleSemanticAction(.shiftEnter)

        case AppKitCommandSelectors.deleteBackward:
            return handleSemanticAction(.deleteBackward)

        case AppKitCommandSelectors.deleteForward:
            emitEditorEvent(.command(.deleteForward))

        case AppKitCommandSelectors.deleteToBeginningOfLine:
            return handleInputCommand(.deleteToTextStart, reportingUnhandled: .deleteToTextStart)

        case AppKitCommandSelectors.deleteWordBackward:
            return handleViewportInputCommand { .deleteWordBackward(viewport: $0) }

        case AppKitCommandSelectors.insertTab:
            handleBlockIndentCommand(.indent)
            return true

        case AppKitCommandSelectors.insertBacktab:
            handleBlockIndentCommand(.outdent)
            return true

        case AppKitCommandSelectors.moveUp:
            return handleViewportInputCommand { .moveUp(viewport: $0) }

        case AppKitCommandSelectors.moveDown:
            return handleViewportInputCommand { .moveDown(viewport: $0) }

        case AppKitCommandSelectors.moveLeft:
            return handleViewportInputCommand { .moveLeft(viewport: $0) }

        case AppKitCommandSelectors.moveRight:
            return handleViewportInputCommand { .moveRight(viewport: $0) }

        case AppKitCommandSelectors.moveToBeginningOfLine:
            return moveToTextBoundary(.start)

        case AppKitCommandSelectors.moveToEndOfLine:
            return moveToTextBoundary(.end)

        case AppKitCommandSelectors.moveToBeginningOfLineAndModifySelection:
            return extendToTextBoundary(.start)

        case AppKitCommandSelectors.moveToEndOfLineAndModifySelection:
            return extendToTextBoundary(.end)

        case AppKitCommandSelectors.moveWordLeft:
            return handleViewportInputCommand { .moveWordLeft(viewport: $0) }

        case AppKitCommandSelectors.moveWordRight:
            return handleViewportInputCommand { .moveWordRight(viewport: $0) }

        case AppKitCommandSelectors.moveWordLeftAndModifySelection:
            return handleViewportInputCommand { .extendWordLeft(viewport: $0) }

        case AppKitCommandSelectors.moveWordRightAndModifySelection:
            return handleViewportInputCommand { .extendWordRight(viewport: $0) }

        case AppKitCommandSelectors.moveLeftAndModifySelection:
            return handleViewportInputCommand { .extendCharacterLeft(viewport: $0) }

        case AppKitCommandSelectors.moveRightAndModifySelection:
            return handleViewportInputCommand { .extendCharacterRight(viewport: $0) }

        case AppKitCommandSelectors.moveUpAndModifySelection:
            return handleViewportInputCommand { .extendUp(viewport: $0) }

        case AppKitCommandSelectors.moveDownAndModifySelection:
            return handleViewportInputCommand { .extendDown(viewport: $0) }

        case AppKitCommandSelectors.cancelOperation:
            return handleSemanticAction(.escape)

        case AppKitCommandSelectors.selectAll:
            return handleSemanticAction(.selectAll)

        case AppKitCommandSelectors.copy:
            return copySelectionToPasteboard()

        case AppKitCommandSelectors.cut:
            guard copySelectionToPasteboard() else { return false }
            return handleInputCommand(.cutSelection, reportingUnhandled: .cutSelection)

        case AppKitCommandSelectors.paste:
            return pasteTextFromPasteboard()

        case AppKitCommandSelectors.undo:
            return handleInputCommand(.undo, reportingUnhandled: .undo)

        case AppKitCommandSelectors.redo:
            return handleInputCommand(.redo, reportingUnhandled: .redo)

        default:
            return false
        }

        requestRender(makeFirstResponder: true, scrollSelectionIntoView: true)
        return true
    }

    // MARK: - Command Helpers

    @discardableResult
    private func moveToTextBoundary(_ direction: TextBoundaryDirection) -> Bool {
        let command: EditorInputEvent.Command
        switch direction {
        case .start:
            command = .moveToTextStart
        case .end:
            command = .moveToTextEnd
        }
        return handleInputCommand(command)
    }

    @discardableResult
    private func extendToTextBoundary(_ direction: TextBoundaryDirection) -> Bool {
        let command: EditorInputEvent.Command
        switch direction {
        case .start:
            command = .extendToTextStart
        case .end:
            command = .extendToTextEnd
        }
        return handleInputCommand(command)
    }

    @discardableResult
    private func handleInputCommand(
        _ command: EditorInputEvent.Command,
        reportingUnhandled action: AppKitEditorAction? = nil
    ) -> Bool {
        guard emitEditorEvent(.command(command)) != nil else {
            guard let action, let owner else { return false }
            // These selectors already returned false — and so fell through the responder
            // chain — when the engine refused them, so that stays the default.
            return owner.reportUnhandledAction(action, defaultHandled: false)
        }
        requestRender(makeFirstResponder: true, scrollSelectionIntoView: true)
        return true
    }

    /// Runs a discrete semantic action and lets the host take it over when the engine
    /// refuses it.
    ///
    /// Only discrete actions route here. Continuous caret navigation is deliberately left
    /// out: "move up at the first line" is a routine boundary hit that happens constantly
    /// during ordinary editing, and reporting it as an escalation would drown the signal
    /// this callback exists to carry.
    private func handleSemanticAction(_ action: AppKitEditorAction) -> Bool {
        guard let owner else { return false }
        guard
            emitEditorEvent(action.inputEvent(viewport: owner.currentViewport()))
                != nil
        else {
            // These selectors reported the command as handled even when the engine refused
            // it, so a host that sets no callback keeps observing exactly that.
            return owner.reportUnhandledAction(action, defaultHandled: true)
        }
        requestRender(makeFirstResponder: true, scrollSelectionIntoView: true)
        return true
    }

    @discardableResult
    /// Every native selector that needs layout resolves through here, which is why the
    /// wrapping into `.navigate` lives at this one point rather than at each call site.
    private func handleViewportInputCommand(
        _ makeCommand: (EditorViewport) -> EditorInputEvent.Command.Navigation
    ) -> Bool {
        let viewport = owner?.currentViewport() ?? EditorViewport(width: 1, scrollY: 0, height: 1)
        return handleInputCommand(.navigate(makeCommand(viewport)))
    }

    private func copySelectionToPasteboard() -> Bool {
        guard let owner else { return false }
        if let plan = owner.clipboardWritePlan() {
            let data = try? JSONEncoder().encode(plan.payload)
            pasteboard.clearContents()
            if let data, data.count <= AppKitClipboardContract.maximumStructuredBytes {
                guard
                    pasteboard.setData(data, forType: AppKitClipboardContract.structuredType)
                else { return false }
            }
            return pasteboard.setString(plan.plainText, forType: .string)
        }
        guard let text = owner.selectedPlainTextForClipboard() else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private func pasteTextFromPasteboard() -> Bool {
        if let data = pasteboard.data(forType: AppKitClipboardContract.structuredType),
            data.count <= AppKitClipboardContract.maximumStructuredBytes,
            let payload = try? JSONDecoder().decode(EditorClipboardPayload.self, from: data),
            payload.version == EditorClipboardPayload.currentVersion
        {
            if handleInputCommand(.pasteStructured(payload)) {
                return true
            }
        }
        guard
            let text = pasteboard.string(forType: .string),
            !text.isEmpty
        else {
            return false
        }
        return handleInputCommand(.pasteText(text))
    }
}

// MARK: - Replacement and Selection Sync

extension AppKitActiveInputController {
    private func applyNativeReplacement(
        _ replacementText: String,
        replacementRange: NSRange,
        blockID: BlockID,
        documentText: String
    ) {
        let replacementRange = normalizedReplacementRange(replacementRange, in: documentText)
        let replacementTextRange =
            replacementRange.slopadTextRange(in: documentText)
            ?? SlopadEngine.TextRange.point(documentText.count)
        text = replacingText(documentText, in: replacementRange, with: replacementText)
        selectedRange = NSRange(
            location: replacementRange.location + replacementText.utf16.count,
            length: 0
        )
        sessionSelectedRange = nil
        markedRange = nil
        markedReplacementRange = nil
        markedDocumentText = nil

        emitEditorEvent(
            .command(
                .replaceText(
                    blockID: blockID,
                    range: replacementTextRange,
                    text: replacementText
                )
            )
        )
        requestRender(makeFirstResponder: true, scrollSelectionIntoView: true)
    }

    // MARK: - Selection Sync

    private func syncSelectionFromNativeSurface() {
        guard let activeTextHostBlockID else { return }
        let range =
            selectedRange.slopadTextRange(in: text) ?? SlopadEngine.TextRange.point(text.count)
        guard sessionSelectedRange != range else { return }
        emitEditorEvent(
            .activeTextSelectionChanged(
                blockID: activeTextHostBlockID,
                selectedRange: range
            )
        )
        sessionSelectedRange = range
    }

    private func clearComposition() {
        emitEditorEvent(.cancelComposition)
        requestRender(makeFirstResponder: true, preserveNativeSurface: true)
    }

    // MARK: - Block Commands

    private func handleBlockIndentCommand(_ direction: BlockIndentDirection) {
        syncSelectionFromNativeSurface()
        let command: EditorInputEvent.Command
        switch direction {
        case .indent:
            command = .indent
        case .outdent:
            command = .outdent
        }
        emitEditorEvent(.command(command))
        requestRender(makeFirstResponder: true, scrollSelectionIntoView: true)
    }

    // MARK: - Text Replacement

    private func replacingText(_ text: String, in range: NSRange, with replacement: String)
        -> String
    {
        guard let swiftRange = Range(range, in: text) else { return text }
        return text.replacingCharacters(in: swiftRange, with: replacement)
    }

    private func normalizedReplacementRange(_ range: NSRange, in text: String) -> NSRange {
        if range.location == NSNotFound {
            return selectedRange
        }
        let maxLength = text.utf16.count
        let location = min(max(range.location, 0), maxLength)
        let length = min(max(range.length, 0), maxLength - location)
        return NSRange(location: location, length: length)
    }

    private func normalizedMarkedSelectionRange(_ range: NSRange, in markedText: String) -> NSRange
    {
        let maxLength = markedText.utf16.count
        let location =
            range.location == NSNotFound
            ? maxLength
            : min(max(range.location, 0), maxLength)
        let length = min(max(range.length, 0), maxLength - location)
        return NSRange(location: location, length: length)
    }

    // MARK: - Render Requests

    private func requestRender(
        makeFirstResponder: Bool,
        preserveNativeSurface: Bool = false,
        scrollSelectionIntoView: Bool = false
    ) {
        owner?.handleActiveInputRenderRequest(
            AppKitActiveInputRenderRequest(
                makeFirstResponder: makeFirstResponder,
                preserveNativeSurface: preserveNativeSurface,
                scrollSelectionIntoView: scrollSelectionIntoView
            )
        )
    }

    @discardableResult
    @inline(__always)
    private func emitEditorEvent(_ inputEvent: EditorInputEvent) -> EditorUpdate? {
        #if DEBUG
            trace(
                AppKitNativeInputTraceEvent(
                    category: .editorEvent,
                    phase: .emitted,
                    editorEvent: AppKitNativeInputTraceEvent.EditorEventName(inputEvent),
                    blockToken: AppKitNativeInputTraceBlockToken.make(activeTextHostBlockID)
                )
            )
        #endif
        let update = owner?.handleNativeInputEvent(inputEvent)
        #if DEBUG
            trace(
                AppKitNativeInputTraceEvent(
                    category: .editorEvent,
                    phase: .result,
                    outcome: update == nil ? .refused : .handled,
                    editorEvent: AppKitNativeInputTraceEvent.EditorEventName(inputEvent),
                    blockToken: AppKitNativeInputTraceBlockToken.make(activeTextHostBlockID),
                    committedRevision: update?.committedDocumentRevision?.rawValue
                )
            )
        #endif
        return update
    }

    #if DEBUG
        private func trace(_ event: @autoclosure () -> AppKitNativeInputTraceEvent) {
            guard let nativeInputTraceHandler else { return }
            nativeInputTraceHandler(event())
        }

        private func traceGuardOutcome(for callback: AppKitNativeInputTraceEvent.Callback) {
            guard nativeInputTraceHandler != nil else { return }
            let accepted = syncGuard.shouldForwardNativeCallback && activeTextHostBlockID != nil
            let reason: AppKitNativeInputTraceEvent.Reason
            if !syncGuard.shouldForwardNativeCallback {
                reason = .sessionSynchronization
            } else if activeTextHostBlockID == nil {
                reason = .missingActiveTextHost
            } else {
                reason = .forwarded
            }
            trace(
                AppKitNativeInputTraceEvent(
                    category: .activeInputGuard,
                    phase: .result,
                    callback: callback,
                    outcome: accepted ? .accepted : .rejected,
                    reason: reason,
                    blockToken: AppKitNativeInputTraceBlockToken.make(activeTextHostBlockID),
                    syncDepth: syncGuard.currentDepth
                )
            )
        }
    #endif
}
