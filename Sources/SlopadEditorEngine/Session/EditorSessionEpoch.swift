import Foundation

// MARK: - EditorSessionEpoch

/// An opaque identity token bound to exactly one `EditorSession` instance.
///
/// Replacing the Session — `resetDocument(blocks:selection:)` is the usual cause — produces
/// a different value. Hosts compare epochs; they never construct one.
///
/// This exists because `EditorDocumentRevision` restarts at zero for every Session. A host
/// that captured "revision 3", let the document be replaced, and later persisted against
/// the new Session's "revision 3" would write the wrong document with no error anywhere.
/// Comparing epochs is what makes that staleness visible as a value comparison instead of
/// a host-maintained generation counter.
///
/// It is deliberately weaker than ``EditorDocumentSource``. That token additionally pins
/// the exact selection because a compare-and-swap patch must not land on a document the
/// caller no longer sees; persistence does not care where the caret is. Widening
/// `EditorDocumentSource` to serve both would make patches accept stale input, so the two
/// tokens stay separate.
///
/// Not `Codable`: the value is meaningful only against a live Session in this process.
/// Decoding one would let a host manufacture a match for a Session that no longer exists,
/// which is precisely the failure the epoch exists to catch.
public struct EditorSessionEpoch: Hashable, Sendable {
    private let rawValue: UUID

    init() {
        self.rawValue = UUID()
    }
}
