import SlopadCoreModel

// MARK: - EffectiveDocumentSnapshot

// Read-only content projection used by layout passes and text measurement. Native marked-text
// callbacks already mutate canonical content live; composition contributes cache identity and
// marked-range runtime state, not a second text overlay.
struct EffectiveDocumentSnapshot {
    let document: Document
    let composition: TextComposition?
    let revision: Int

    init(document: Document, composition: TextComposition? = nil) {
        self.document = document
        self.composition = composition
        self.revision = document.revision
    }

    var compositionRevision: Int {
        composition?.compositionRevision ?? 0
    }

    func block(for blockID: BlockID) -> Block? {
        document.block(blockID)
    }
}
