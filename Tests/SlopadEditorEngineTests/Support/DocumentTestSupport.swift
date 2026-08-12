import SlopadCoreModel

func makeFlatDocument(_ blocks: [Block]) -> Document {
    var document = Document()
    for block in blocks {
        document.appendRoot(block)
    }
    return document
}

extension Document {
    mutating func appendRoot(_ block: Block) {
        if case .failure(let failure) = insertBlock(block, parentID: nil) {
            preconditionFailure("appendRoot failed: \(failure)")
        }
    }

    mutating func appendChild(_ block: Block, to parentID: BlockID) {
        if case .failure(let failure) = insertBlock(block, parentID: parentID) {
            preconditionFailure("appendChild failed: \(failure)")
        }
    }
}
