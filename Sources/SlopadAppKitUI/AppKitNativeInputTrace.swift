#if DEBUG
    import AppKit
    import SlopadEngine

    // MARK: - AppKitNativeInputTraceHandler

    /// Package-only diagnostic transport used by SlopadDebugApp and focused adapter tests.
    ///
    /// The trace is deliberately unavailable to ordinary hosts. It observes the production
    /// AppKit callback path without becoming an editor command or canonical-state source.
    package typealias AppKitNativeInputTraceHandler =
        @MainActor (AppKitNativeInputTraceEvent) -> Void

    // MARK: - AppKitNativeInputTraceEvent

    package struct AppKitNativeInputTraceEvent: Encodable, Equatable {
        package enum Category: String, Encodable {
            case focus
            case keyDown
            case interpretKeyEvents
            case textCallback
            case activeInputGuard
            case editorEvent
            case nativeSurfaceSync
            case firstRect
        }

        package enum Phase: String, Encodable {
            case received
            case routed
            case before
            case during
            case after
            case became
            case resigned
            case emitted
            case result
        }

        package enum Callback: String, Encodable {
            case insertText
            case setMarkedText
            case unmarkText
        }

        package enum Route: String, Encodable {
            case nativeCommand
            case shiftReturnCommand
            case tabCommand
            case interpretKeyEvents
        }

        package enum Outcome: String, Encodable {
            case accepted
            case rejected
            case handled
            case refused
        }

        package enum Reason: String, Encodable {
            case forwarded
            case sessionSynchronization
            case missingActiveTextHost
            case unsupportedTextPayload
            case callbackHasNoSyncGuard
        }

        package enum EditorEventName: String, Encodable {
            case activeTextSelectionChanged
            case beginComposition
            case updateComposition
            case commitComposition
            case cancelComposition
            case replaceText
            case command
            case pointer
        }

        package let category: Category
        package let phase: Phase
        package let callback: Callback?
        package let route: Route?
        package let outcome: Outcome?
        package let reason: Reason?
        package let editorEvent: EditorEventName?
        package let selector: String?
        package let text: AppKitNativeInputTraceText?
        package let selectedRange: AppKitNativeInputTraceRange?
        package let replacementRange: AppKitNativeInputTraceRange?
        package let requestedRange: AppKitNativeInputTraceRange?
        package let resultRect: AppKitNativeInputTraceRect?
        package let resultAvailable: Bool?
        package let blockID: String?
        package let syncDepth: Int?
        package let committedRevision: UInt64?
        package let canvasIsFirstResponder: Bool?
        package let inputContextAvailable: Bool?
        package let inputSourceID: String?
        /// This trace observes invalidation state; it never calls AppKit invalidation APIs.
        package let characterCoordinatesInvalidated: Bool?

        init(
            category: Category,
            phase: Phase,
            callback: Callback? = nil,
            route: Route? = nil,
            outcome: Outcome? = nil,
            reason: Reason? = nil,
            editorEvent: EditorEventName? = nil,
            selector: String? = nil,
            text: AppKitNativeInputTraceText? = nil,
            selectedRange: AppKitNativeInputTraceRange? = nil,
            replacementRange: AppKitNativeInputTraceRange? = nil,
            requestedRange: AppKitNativeInputTraceRange? = nil,
            resultRect: AppKitNativeInputTraceRect? = nil,
            resultAvailable: Bool? = nil,
            blockID: String? = nil,
            syncDepth: Int? = nil,
            committedRevision: UInt64? = nil,
            canvasIsFirstResponder: Bool? = nil,
            inputContextAvailable: Bool? = nil,
            inputSourceID: String? = nil,
            characterCoordinatesInvalidated: Bool? = nil
        ) {
            self.category = category
            self.phase = phase
            self.callback = callback
            self.route = route
            self.outcome = outcome
            self.reason = reason
            self.editorEvent = editorEvent
            self.selector = selector
            self.text = text
            self.selectedRange = selectedRange
            self.replacementRange = replacementRange
            self.requestedRange = requestedRange
            self.resultRect = resultRect
            self.resultAvailable = resultAvailable
            self.blockID = blockID
            self.syncDepth = syncDepth
            self.committedRevision = committedRevision
            self.canvasIsFirstResponder = canvasIsFirstResponder
            self.inputContextAvailable = inputContextAvailable
            self.inputSourceID = inputSourceID
            self.characterCoordinatesInvalidated = characterCoordinatesInvalidated
        }
    }

    // MARK: - Bounded Values

    package struct AppKitNativeInputTraceText: Encodable, Equatable {
        package static let maximumCharacterCount = 16

        package let value: String
        package let utf16Length: Int
        package let truncated: Bool

        init(_ text: String) {
            value = String(text.prefix(Self.maximumCharacterCount))
            utf16Length = text.utf16.count
            truncated = text.count > Self.maximumCharacterCount
        }
    }

    package struct AppKitNativeInputTraceRange: Encodable, Equatable {
        package let location: Int?
        package let length: Int
        package let isNotFound: Bool

        init(_ range: NSRange) {
            isNotFound = range.location == NSNotFound
            location = isNotFound ? nil : range.location
            length = range.length
        }
    }

    package struct AppKitNativeInputTraceRect: Encodable, Equatable {
        package let x: Double
        package let y: Double
        package let width: Double
        package let height: Double

        init(_ rect: NSRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.size.width
            height = rect.size.height
        }
    }

    // MARK: - Editor Event Classification

    extension AppKitNativeInputTraceEvent.EditorEventName {
        init(_ inputEvent: EditorInputEvent) {
            switch inputEvent {
            case .activeTextSelectionChanged:
                self = .activeTextSelectionChanged
            case .beginComposition:
                self = .beginComposition
            case .updateComposition:
                self = .updateComposition
            case .commitComposition:
                self = .commitComposition
            case .cancelComposition:
                self = .cancelComposition
            case .command(.replaceText):
                self = .replaceText
            case .command:
                self = .command
            case .pointer:
                self = .pointer
            }
        }
    }
#endif
