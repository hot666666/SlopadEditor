// MARK: - Editor Selection Identity

/// Model-issued O(1) identity for one exact canonical selection generation.
///
/// Consumers use this instead of hashing or comparing `EditorSelection`, whose block
/// selection payload may contain thousands of IDs. The model advances the identity only
/// after a successful transition changes the exact selection value.
package struct EditorSelectionIdentity: Hashable, Sendable {
    let rawValue: UInt64
}
