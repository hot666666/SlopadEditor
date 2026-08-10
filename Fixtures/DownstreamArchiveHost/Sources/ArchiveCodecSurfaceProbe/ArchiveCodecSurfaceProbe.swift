import Foundation
import SlopadArchive

@main
private struct ArchiveCodecSurfaceProbe {
    static func main() throws {
        let rootID: BlockID = "archive-root"
        let childID: BlockID = "archive-child"
        let blocks = [
            EditorBlockInput(
                id: rootID,
                kind: .heading(level: .h2),
                content: BlockContent(
                    text: "Public archive facade",
                    marks: [
                        BlockContent.InlineMark(
                            kind: .strong,
                            range: TextRange(0, 6)
                        ),
                        BlockContent.InlineMark(
                            kind: .link(destination: "https://example.com"),
                            range: TextRange(7, 14)
                        ),
                    ]
                )
            ),
            EditorBlockInput(
                id: childID,
                parentID: rootID,
                kind: .orderedListItem(restartNumber: 3),
                content: BlockContent(text: "child")
            ),
        ]

        let data = try SlopadArchive.encode(blocks)
        let decoded = try SlopadArchive.decode(data)
        precondition(decoded == blocks)
    }
}
