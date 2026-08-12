import SlopadCoreModel

// MARK: - EffectiveDocumentSnapshot

// Read-only content projection(컨텐츠 반영본 = 원본이 아니라 소비 목적에 맞게 계산된 view) used by layout passes
// and text measurement when they need Document blocks with the current live composition applied.
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
        guard var block = document.block(blockID) else { return nil }
        guard let composition, composition.blockID == blockID else { return block }
        let canonicalRevision = block.content.revision
        block.content.delete(composition.replacementRange)
        block.content.insert(composition.text, at: composition.replacementRange.lowerBound)
        block.content.revision = canonicalRevision
        return block
    }
}
