import AppKit
import SlopadEngine

// MARK: - AppKitActiveInputOwner

@MainActor
protocol AppKitActiveInputOwner: AnyObject {
    func documentTextForNativeInput(blockID: BlockID) -> String?
    func selectedPlainTextForClipboard() -> String?
    @discardableResult
    func handleNativeInputEvent(_ inputEvent: EditorInputEvent) -> EditorUpdate?
    func handleActiveInputRenderRequest(_ request: AppKitActiveInputRenderRequest)
    func currentViewport() -> EditorViewport
}

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
    private let syncGuard = SyncGuard()

    // MARK: - State

    private var activeTextHostBlockID: BlockID?
    private var text = ""
    private var selectedRange = NSRange(location: 0, length: 0)
    private var sessionSelectedRange: SlopadEngine.TextRange?
    private var markedRange: NSRange?
    private var markedReplacementRange: NSRange?
    private var markedDocumentText: String?

    // MARK: - Init

    init(owner: any AppKitActiveInputOwner) {
        self.owner = owner
    }

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
        activeTextHostBlockID = nil
        syncGuard.performSessionSync {
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
        owner?.handleNativeInputEvent(compositionEvent)
        if let effectiveSelectedRange = selectedRange.slopadTextRange(in: text) {
            let update = owner?.handleNativeInputEvent(
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
        markedRange = nil
        markedReplacementRange = nil
        markedDocumentText = nil
        sessionSelectedRange = nil
        owner?.handleNativeInputEvent(.commitComposition)
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
        owner?.handleNativeInputEvent(
            .command(
                .replaceText(
                    blockID: blockID,
                    range: replacementTextRange,
                    text: newText
                )
            )
        )

        if let preservedRange {
            owner?.handleNativeInputEvent(
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
            owner?.handleNativeInputEvent(.command(.enter))

        case AppKitCommandSelectors.insertLineBreak,
            AppKitCommandSelectors.insertNewlineIgnoringFieldEditor:
            owner?.handleNativeInputEvent(.command(.shiftEnter))

        case AppKitCommandSelectors.deleteBackward:
            owner?.handleNativeInputEvent(.command(.deleteBackward))

        case AppKitCommandSelectors.deleteForward:
            owner?.handleNativeInputEvent(.command(.deleteForward))

        case AppKitCommandSelectors.deleteToBeginningOfLine:
            return handleInputCommand(.deleteToTextStart)

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
            owner?.handleNativeInputEvent(.command(.escape))

        case AppKitCommandSelectors.selectAll:
            owner?.handleNativeInputEvent(.command(.selectAll))

        case AppKitCommandSelectors.copy:
            return copySelectionToPasteboard()

        case AppKitCommandSelectors.cut:
            guard copySelectionToPasteboard() else { return false }
            return handleInputCommand(.cutSelection)

        case AppKitCommandSelectors.paste:
            return pasteTextFromPasteboard()

        case AppKitCommandSelectors.undo:
            return handleInputCommand(.undo)

        case AppKitCommandSelectors.redo:
            return handleInputCommand(.redo)

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
    private func handleInputCommand(_ command: EditorInputEvent.Command) -> Bool {
        guard owner?.handleNativeInputEvent(.command(command)) != nil else {
            return false
        }
        requestRender(makeFirstResponder: true, scrollSelectionIntoView: true)
        return true
    }

    @discardableResult
    private func handleViewportInputCommand(
        _ makeCommand: (EditorViewport) -> EditorInputEvent.Command
    ) -> Bool {
        let viewport = owner?.currentViewport() ?? EditorViewport(width: 1, scrollY: 0, height: 1)
        return handleInputCommand(makeCommand(viewport))
    }

    private func copySelectionToPasteboard() -> Bool {
        guard let text = owner?.selectedPlainTextForClipboard() else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private func pasteTextFromPasteboard() -> Bool {
        guard
            let text = NSPasteboard.general.string(forType: .string),
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

        owner?.handleNativeInputEvent(
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
        let range = selectedRange.slopadTextRange(in: text) ?? SlopadEngine.TextRange.point(text.count)
        guard sessionSelectedRange != range else { return }
        owner?.handleNativeInputEvent(
            .activeTextSelectionChanged(
                blockID: activeTextHostBlockID,
                selectedRange: range
            )
        )
        sessionSelectedRange = range
    }

    private func clearComposition() {
        owner?.handleNativeInputEvent(.cancelComposition)
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
        owner?.handleNativeInputEvent(.command(command))
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

    private func normalizedMarkedSelectionRange(_ range: NSRange, in markedText: String) -> NSRange {
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
}
