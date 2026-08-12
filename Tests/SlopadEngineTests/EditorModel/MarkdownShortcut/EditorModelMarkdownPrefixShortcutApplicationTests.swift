import Testing

import SlopadCoreModel
import SlopadEditorDocumentModel

@Suite("EditorModel 마크다운 prefix shortcut 적용")
struct EditorModelMarkdownPrefixShortcutApplicationTests {
    @Test("공백 입력으로 prefix가 완성되면 block kind를 바꾸고 prefix를 제거한다")
    func givenPrefixAlreadyTyped_whenSpaceIsInserted_thenShortcutConsumesPrefix() throws {
        // Given
        let cases: [(prefix: String, expectedKind: BlockKind)] = [
            ("#", .heading(level: .h1)),
            ("##", .heading(level: .h2)),
            ("###", .heading(level: .h3)),
            ("-", .unorderedListItem),
            ("*", .unorderedListItem),
            (">", .quote),
            ("0.", .orderedListItem(restartNumber: 0)),
            ("1.", .orderedListItem(restartNumber: nil)),
            ("10.", .orderedListItem(restartNumber: 10)),
            ("[x]", .todo(isChecked: true)),
            ("[X]", .todo(isChecked: true)),
            ("[ ]", .todo(isChecked: false)),
            ("[]", .todo(isChecked: false)),
        ]
        var results: [(kind: BlockKind, text: String, appliedShortcut: Bool)] = []

        // When
        for (index, testCase) in cases.enumerated() {
            let blockID = BlockID("space-prefix-\(index)")
            let editor = EditorModel(
                document: .singleParagraph("", id: blockID),
                selection: .caret(blockID: blockID, offset: 0)
            )

            _ = editor.apply(.insertText(testCase.prefix))
            let result = editor.apply(.insertText(" "))

            let block = try #require(editor.document.blocks[blockID])
            results.append(
                (
                    kind: block.kind,
                    text: block.content.text,
                    appliedShortcut: result.outcome?.change.operations.contains { operation in
                        if case .refreshMarker = operation {
                            return true
                        }
                        return false
                    } ?? false
                )
            )
        }

        // Then
        for (result, testCase) in zip(results, cases) {
            #expect(result.kind == testCase.expectedKind, "prefix \(testCase.prefix)")
            #expect(result.text == "", "prefix \(testCase.prefix)")
            #expect(result.appliedShortcut, "prefix \(testCase.prefix)")
        }
    }

    @Test("문단이 아닌 블록에서도 공백 입력으로 prefix가 완성되면 block kind를 바꾼다")
    func givenNonParagraphBlock_whenSpaceCompletesPrefix_thenShortcutChangesKind() throws {
        // Given
        let blockID: BlockID = "non-paragraph-prefix"
        var document = Document.singleParagraph("", id: blockID)
        try document.setBlockKind(blockID: blockID, kind: .heading(level: .h2)).get()
        let editor = EditorModel(
            document: document,
            selection: .caret(blockID: blockID, offset: 0)
        )
        let expectedKind = BlockKind.unorderedListItem
        let expectedText = ""

        // When
        _ = editor.apply(.insertText("-"))
        let result = editor.apply(.insertText(" "))

        // Then
        let block = try #require(editor.document.blocks[blockID])
        #expect(block.kind == expectedKind)
        #expect(block.content.text == expectedText)
        #expect(result.outcome?.change.operations.contains { operation in
            if case .refreshMarker = operation {
                return true
            }
            return false
        } == true)
    }

    @Test("heading marker를 문단 시작에 삽입하면 heading kind로 바꾸고 marker를 제거한다")
    func givenHeadingMarkers_whenInsertTextRuns_thenMarkerBecomesHeading() throws {
        // Given
        let cases: [(marker: String, expectedKind: BlockKind)] = [
            ("# ", .heading(level: .h1)),
            ("## ", .heading(level: .h2)),
            ("### ", .heading(level: .h3)),
        ]
        let expectedText = ""
        var results: [(kind: BlockKind, text: String)] = []

        // When
        for (index, testCase) in cases.enumerated() {
            let blockID = BlockID("heading-\(index)")
            let editor = EditorModel(
                document: .singleParagraph("", id: blockID),
                selection: .caret(blockID: blockID, offset: 0)
            )

            _ = editor.apply(.insertText(testCase.marker))

            let block = try #require(editor.document.blocks[blockID])
            results.append((kind: block.kind, text: block.content.text))
        }

        // Then
        for (result, testCase) in zip(results, cases) {
            #expect(result.kind == testCase.expectedKind, "marker \(testCase.marker)")
            #expect(result.text == expectedText, "marker \(testCase.marker)")
        }
    }

    @Test("list marker를 문단 시작에 삽입하면 list item kind로 바꾸고 marker를 제거한다")
    func givenListMarkers_whenInsertTextRuns_thenMarkerBecomesListItem() throws {
        // Given
        let cases: [(marker: String, expectedKind: BlockKind)] = [
            ("- ", .unorderedListItem),
            ("* ", .unorderedListItem),
        ]
        let expectedText = ""
        var results: [(kind: BlockKind, text: String)] = []

        // When
        for (index, testCase) in cases.enumerated() {
            let blockID = BlockID("list-\(index)")
            let editor = EditorModel(
                document: .singleParagraph("", id: blockID),
                selection: .caret(blockID: blockID, offset: 0)
            )

            _ = editor.apply(.insertText(testCase.marker))

            let block = try #require(editor.document.blocks[blockID])
            results.append((kind: block.kind, text: block.content.text))
        }

        // Then
        for (result, testCase) in zip(results, cases) {
            #expect(result.kind == testCase.expectedKind, "marker \(testCase.marker)")
            #expect(result.text == expectedText, "marker \(testCase.marker)")
        }
    }

    @Test("ordered marker를 문단 시작에 삽입하면 ordered list item kind로 바꾸고 marker를 제거한다")
    func givenOrderedMarkers_whenInsertTextRuns_thenMarkerBecomesOrderedItem() throws {
        // Given
        let cases: [(marker: String, expectedKind: BlockKind)] = [
            ("0. ", .orderedListItem(restartNumber: 0)),
            ("1. ", .orderedListItem(restartNumber: nil)),
            ("10. ", .orderedListItem(restartNumber: 10)),
            ("1000. ", .orderedListItem(restartNumber: 1000)),
            ("123456789. ", .orderedListItem(restartNumber: 123_456_789)),
        ]
        let expectedText = ""
        var results: [(kind: BlockKind, text: String)] = []

        // When
        for (index, testCase) in cases.enumerated() {
            let blockID = BlockID("ordered-\(index)")
            let editor = EditorModel(
                document: .singleParagraph("", id: blockID),
                selection: .caret(blockID: blockID, offset: 0)
            )

            _ = editor.apply(.insertText(testCase.marker))

            let block = try #require(editor.document.blocks[blockID])
            results.append((kind: block.kind, text: block.content.text))
        }

        // Then
        for (result, testCase) in zip(results, cases) {
            #expect(result.kind == testCase.expectedKind, "marker \(testCase.marker)")
            #expect(result.text == expectedText, "marker \(testCase.marker)")
        }
    }

    @Test("quote, todo, code marker를 문단 시작에 삽입하면 대응 block kind로 바꾸고 marker를 제거한다")
    func givenOtherBlockMarkers_whenInsertTextRuns_thenMarkerBecomesBlockKind() throws {
        // Given
        let cases: [(marker: String, expectedKind: BlockKind)] = [
            ("> ", .quote),
            ("[] ", .todo(isChecked: false)),
            ("[ ] ", .todo(isChecked: false)),
            ("[x] ", .todo(isChecked: true)),
            ("[X] ", .todo(isChecked: true)),
            ("```", .codeBlock(language: nil)),
        ]
        let expectedText = ""
        var results: [(kind: BlockKind, text: String)] = []

        // When
        for (index, testCase) in cases.enumerated() {
            let blockID = BlockID("block-prefix-\(index)")
            let editor = EditorModel(
                document: .singleParagraph("", id: blockID),
                selection: .caret(blockID: blockID, offset: 0)
            )

            _ = editor.apply(.insertText(testCase.marker))

            let block = try #require(editor.document.blocks[blockID])
            results.append((kind: block.kind, text: block.content.text))
        }

        // Then
        for (result, testCase) in zip(results, cases) {
            #expect(result.kind == testCase.expectedKind, "marker \(testCase.marker)")
            #expect(result.text == expectedText, "marker \(testCase.marker)")
        }
    }
}
