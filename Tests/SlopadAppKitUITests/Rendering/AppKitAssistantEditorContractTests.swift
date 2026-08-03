import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AssistantEditorContract AppKit 문서 context와 patch")
struct AppKitAssistantEditorContractTests {
    @Test("성공 patch callback은 같은 revision의 context를 읽고 surface를 한 번 동기화한다")
    func publishesMatchingContextOnce() throws {
        // Given
        let a: BlockID = "a"
        let b: BlockID = "b"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(id: a, content: BlockContent(text: "A")),
                EditorBlockInput(id: b, content: BlockContent(text: "B")),
            ],
            selection: .caret(blockID: a, offset: 1)
        )
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let sourceContext = try controller.documentContextSnapshot()
        let replacement = [
            EditorBlockInput(id: b, kind: .quote, content: BlockContent(text: "B changed")),
            EditorBlockInput(id: a, kind: .heading(level: .h2), content: BlockContent(text: "A")),
        ]
        let selectionAfter: EditorSelection = .caret(blockID: b, offset: 3)
        let patch = EditorDocumentPatch(
            source: sourceContext.source,
            replacementBlocks: replacement,
            selectionAfter: selectionAfter
        )
        var callbackCount = 0
        var callbackContext: EditorDocumentContextSnapshot?
        controller.onUpdate = { [weak controller] update in
            guard let controller else { return }
            callbackCount += 1
            let context = try? controller.documentContextSnapshot()
            #expect(context?.document.revision == update.committedDocumentRevision)
            #expect(context?.selection == update.selection)
            callbackContext = context
        }

        // When
        let appliedUpdate = try controller.applyDocumentPatch(patch)
        let update = try #require(appliedUpdate)
        let noOpContext = try controller.documentContextSnapshot()
        let noOp = try controller.applyDocumentPatch(
            EditorDocumentPatch(
                source: noOpContext.source,
                replacementBlocks: noOpContext.document.blocks,
                selectionAfter: noOpContext.selection
            )
        )

        // Then
        #expect(callbackCount == 1)
        #expect(update.committedDocumentRevision?.rawValue == 1)
        #expect(callbackContext?.document.blocks == replacement)
        #expect(callbackContext?.selection == selectionAfter)
        #expect(controller.documentSnapshot.blocks == replacement)
        #expect(controller.snapshot?.selection == selectionAfter)
        #expect(controller.snapshot?.visibleBlocks.map(\.id) == [b, a])
        #expect(controller.activeNativeText == "B changed")
        #expect(noOp == nil)
    }

    @Test("동일 revision과 selection으로 reset되어도 이전 Session source는 ABA stale이다")
    func rejectsResetABA() throws {
        // Given
        let blockID: BlockID = "block"
        let blocks = [EditorBlockInput(id: blockID, content: BlockContent(text: "same"))]
        let selection: EditorSelection = .caret(blockID: blockID, offset: 2)
        let controller = AppKitEditorViewController(blocks: blocks, selection: selection)
        let oldContext = try controller.documentContextSnapshot()
        controller.resetDocument(blocks: blocks, selection: selection)
        let patch = EditorDocumentPatch(
            source: oldContext.source,
            replacementBlocks: [
                EditorBlockInput(id: blockID, content: BlockContent(text: "changed"))
            ],
            selectionAfter: .caret(blockID: blockID, offset: 7)
        )

        // When
        let error = captureAppKitContractError {
            try controller.applyDocumentPatch(patch)
        }

        // Then
        #expect(controller.documentSnapshot.revision.rawValue == 0)
        #expect(error == .staleSource)
        #expect(controller.documentSnapshot.blocks == blocks)
    }

    @Test("native marked text 중 query와 apply는 commit을 요구하는 typed error를 반환한다")
    func rejectsNativeComposition() throws {
        // Given
        let blockID: BlockID = "block"
        let controller = AppKitEditorViewController(
            blocks: [EditorBlockInput(id: blockID, content: BlockContent(text: "AB"))],
            selection: .caret(blockID: blockID, offset: 1)
        )
        controller.renderAndSyncSurface(makeFirstResponder: false)
        let context = try controller.documentContextSnapshot()
        controller.setMarkedTextFromNativeSurface(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let patch = EditorDocumentPatch(
            source: context.source,
            replacementBlocks: context.document.blocks,
            selectionAfter: context.selection
        )

        // When
        let queryError = captureAppKitContractError {
            try controller.documentContextSnapshot()
        }
        let applyError = captureAppKitContractError {
            try controller.applyDocumentPatch(patch)
        }

        // Then
        #expect(queryError == .activeComposition)
        #expect(applyError == .activeComposition)
        #expect(controller.hasActiveNativeMarkedText)
        #expect(controller.snapshot?.composition != nil)
    }
}

@MainActor
private func captureAppKitContractError<T>(
    _ operation: () throws -> T
) -> EditorDocumentTransactionError? {
    do {
        _ = try operation()
        return nil
    } catch let error as EditorDocumentTransactionError {
        return error
    } catch {
        Issue.record("예상하지 못한 error: \(error)")
        return nil
    }
}
