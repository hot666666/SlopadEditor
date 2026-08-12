// MARK: - Selection Plain Text

extension EditorSession {
    public func selectedPlainText() -> String? {
        clipboardWritePlan()?.plainText
    }
}
