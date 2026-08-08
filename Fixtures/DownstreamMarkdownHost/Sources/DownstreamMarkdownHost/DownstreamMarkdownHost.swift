import SlopadEngine
import SlopadMarkdown

private struct FixtureTextLayouter: BlockTextLayoutProtocol {
    func measure(_ request: BlockMeasureRequest) -> BlockMeasurement {
        BlockMeasurement(height: 20)
    }

    func textFrame(
        for request: BlockMeasureRequest,
        measuredHeight: Double?
    ) -> EditorRect {
        EditorRect(
            x: 0,
            y: 0,
            width: request.availableWidth,
            height: measuredHeight ?? 20
        )
    }

    func lineFragments(for request: BlockMeasureRequest) -> [LineFragmentSnapshot] {
        []
    }

    func caretRect(
        for position: TextPosition,
        in request: BlockMeasureRequest
    ) -> EditorRect? {
        nil
    }

    func selectionRects(
        for range: TextRange,
        in request: BlockMeasureRequest
    ) -> [EditorRect] {
        []
    }

    func textPosition(
        at point: EditorPoint,
        in request: BlockMeasureRequest
    ) -> TextPosition {
        TextPosition(blockID: request.blockID, offset: 0)
    }
}

@main
private struct DownstreamMarkdownHost {
    static func main() throws {
        let session = EditorSession(
            blocks: [EditorBlockInput(content: BlockContent(text: "Before import"))],
            selection: .inactive,
            textLayouter: FixtureTextLayouter()
        )
        let decodedBlocks = try SlopadMarkdown.decode(
            "# Imported\n\n- first\n  - nested"
        )
        let context = try session.documentContextSnapshot()

        _ = try session.applyDocumentPatch(
            EditorDocumentPatch(
                source: context.source,
                replacementBlocks: decodedBlocks,
                selectionAfter: .inactive
            )
        )

        precondition(session.documentSnapshot.blocks == decodedBlocks)
    }
}
