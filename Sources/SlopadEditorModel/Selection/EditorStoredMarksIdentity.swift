// MARK: - Editor Stored Marks Identity

/// Model-issued O(1) identity for the exact stored-mark set used by caret commands.
///
/// This is deliberately separate from selection identity: toggling or clearing a stored
/// mark changes command facts without moving the caret.
package struct EditorStoredMarksIdentity: Hashable, Sendable {
    let rawValue: UInt64
}
