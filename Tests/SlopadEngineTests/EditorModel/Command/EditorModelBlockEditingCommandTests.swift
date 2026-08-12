import Testing

import SlopadCoreModel
import SlopadEditorDocumentModel

@Suite("EditorModel 블록 편집 명령")
struct EditorModelBlockEditingCommandTests {
    @Test("splitBlock은 원본 텍스트를 나누고 새 블록으로 캐럿을 이동한다")
    func givenParagraph_whenSplitBlockRuns_thenTextIsSplitAndCaretMovesToCreatedBlock() throws {
        // Given
        let blockID: BlockID = "block"
        let editor = EditorModel(
            document: .singleParagraph("HelloWorld", id: blockID),
            selection: .caret(blockID: blockID, offset: 0)
        )
        let expectedOriginalText = "Hello"
        let expectedCreatedText = "World"
        let expectedCreatedOffset = 0

        // When
        let result = editor.apply(.splitBlock(blockID: blockID, offset: 5))

        // Then
        let change = try #require(result.outcome?.change)
        let createdID = try #require(createdBlockID(in: change))
        #expect(editor.document.blocks[blockID]?.content.text == expectedOriginalText)
        #expect(editor.document.blocks[createdID]?.content.text == expectedCreatedText)
        #expect(editor.selection == .caret(blockID: createdID, offset: expectedCreatedOffset))
    }

    @Test("자식이 있는 블록을 splitBlock하면 자식은 새 블록으로 이동한다")
    func givenBlockWithChild_whenSplitBlockRuns_thenChildrenTransferToCreatedBlock() throws {
        // Given
        let parent: BlockID = "parent"
        let child: BlockID = "child"
        var document = Document.singleParagraph("HelloWorld", id: parent)
        document.appendChild(Block(id: child, content: BlockContent(text: "child")), to: parent)
        let editor = EditorModel(document: document, selection: .caret(blockID: parent, offset: 0))
        let expectedOriginalChildIDs: [BlockID] = []
        let expectedCreatedChildIDs = [child]

        // When
        let result = editor.apply(.splitBlock(blockID: parent, offset: 5))

        // Then
        let change = try #require(result.outcome?.change)
        let createdID = try #require(createdBlockID(in: change))
        #expect(editor.document.blocks[parent]?.childIDs == expectedOriginalChildIDs)
        #expect(editor.document.blocks[createdID]?.childIDs == expectedCreatedChildIDs)
        #expect(editor.document.blocks[child]?.parentID == createdID)
    }

    @Test("재시작 번호가 있는 ordered 블록을 splitBlock하면 새 블록은 자동 번호를 사용한다")
    func givenRestartedOrderedBlock_whenSplitBlockRuns_thenCreatedBlockUsesAutoNumber() throws {
        // Given
        let blockID: BlockID = "ordered"
        var document = Document.singleParagraph("ab", id: blockID)
        try document.setBlockKind(blockID: blockID, kind: .orderedListItem(restartNumber: 10)).get()
        let editor = EditorModel(
            document: document, selection: .caret(blockID: blockID, offset: 0))
        let expectedOriginalKind = BlockKind.orderedListItem(restartNumber: 10)
        let expectedCreatedKind = BlockKind.orderedListItem(restartNumber: nil)

        // When
        let result = editor.apply(.splitBlock(blockID: blockID, offset: 1))

        // Then
        let change = try #require(result.outcome?.change)
        let createdID = try #require(createdBlockID(in: change))
        #expect(editor.document.blocks[blockID]?.kind == expectedOriginalKind)
        #expect(editor.document.blocks[createdID]?.kind == expectedCreatedKind)
    }

    @Test("heading 블록을 splitBlock하면 새 블록은 문단이 된다")
    func givenHeadingBlock_whenSplitBlockRuns_thenCreatedBlockBecomesParagraph() throws {
        // Given
        let blockID: BlockID = "heading"
        var document = Document.singleParagraph("Title", id: blockID)
        try document.setBlockKind(blockID: blockID, kind: .heading(level: .h1)).get()
        let editor = EditorModel(
            document: document,
            selection: .caret(blockID: blockID, offset: 0)
        )
        let expectedOriginalKind = BlockKind.heading(level: .h1)
        let expectedCreatedKind = BlockKind.paragraph

        // When
        let result = editor.apply(.splitBlock(blockID: blockID, offset: 5))

        // Then
        let change = try #require(result.outcome?.change)
        let createdID = try #require(createdBlockID(in: change))
        #expect(editor.document.blocks[blockID]?.kind == expectedOriginalKind)
        #expect(editor.document.blocks[createdID]?.kind == expectedCreatedKind)
    }

    @Test("unordered 블록을 splitBlock하면 새 블록도 unordered가 된다")
    func givenUnorderedBlock_whenSplitBlockRuns_thenCreatedBlockKeepsListKind() throws {
        // Given
        let blockID: BlockID = "unordered"
        var document = Document.singleParagraph("Item", id: blockID)
        try document.setBlockKind(blockID: blockID, kind: .unorderedListItem).get()
        let editor = EditorModel(
            document: document,
            selection: .caret(blockID: blockID, offset: 0)
        )
        let expectedCreatedKind = BlockKind.unorderedListItem

        // When
        let result = editor.apply(.splitBlock(blockID: blockID, offset: 4))

        // Then
        let change = try #require(result.outcome?.change)
        let createdID = try #require(createdBlockID(in: change))
        #expect(editor.document.blocks[createdID]?.kind == expectedCreatedKind)
    }

    @Test("자식이 있는 source 블록을 mergeBlocks하면 자식이 target에 이어 붙는다")
    func givenMergeSourceWithChildren_whenMerged_thenChildrenAppendToTarget() throws {
        // Given
        let target: BlockID = "target"
        let source: BlockID = "source"
        let targetChild: BlockID = "target-child"
        let sourceChild: BlockID = "source-child"
        var document = makeFlatDocument([
            Block(id: target, content: BlockContent(text: "A")),
            Block(id: source, content: BlockContent(text: "B")),
        ])
        document.appendChild(Block(id: targetChild), to: target)
        document.appendChild(Block(id: sourceChild), to: source)
        let editor = EditorModel(document: document, selection: .caret(blockID: source, offset: 0))
        let expectedMergedChildIDs = [targetChild, sourceChild]
        let expectedSourceChildParentID = target

        // When
        _ = editor.apply(.mergeBlocks(target: target, source: source))

        // Then
        let merged = try #require(editor.document.blocks[target])
        #expect(merged.childIDs == expectedMergedChildIDs)
        #expect(editor.document.blocks[sourceChild]?.parentID == expectedSourceChildParentID)
        #expect(editor.document.blocks[source] == nil)
    }
}

// MARK: - Split Operation Inspection

extension EditorModelBlockEditingCommandTests {
    private func createdBlockID(in change: EditorChange) -> BlockID? {
        change.operations.compactMap { operation -> BlockID? in
            if case .splitBlock(_, let created) = operation { return created }
            return nil
        }.first
    }
}
