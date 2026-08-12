import SlopadCoreModel

// MARK: - Input Event Dispatch

extension EditorSession {
    @discardableResult
    public func handleInput(_ inputEvent: EditorInputEvent) -> EditorUpdate? {
        let update: EditorUpdate?
        switch inputEvent {
        case .command(let command):
            update = handleInputCommand(command)

        case .pointer(let pointerEvent):
            update = handlePointerEvent(pointerEvent)

        case .activeTextSelectionChanged(let blockID, let selectedRange):
            update = handleActiveTextSelectionChanged(blockID: blockID, selectedRange: selectedRange)

        case .beginComposition(let blockID, let replacementRange, let text),
            .updateComposition(let blockID, let replacementRange, let text):
            guard canReceiveCompositionInput(blockID: blockID) else { return nil }
            update = setComposition(
                nextTextComposition(
                    blockID: blockID,
                    replacementRange: replacementRange,
                    text: text
                )
            )

        case .commitComposition:
            update = endComposition(commit: true)

        case .cancelComposition:
            update = endComposition(commit: false)
        }
        updateSlashCommandRuntime(after: inputEvent, update: update)
        return update
    }
}
