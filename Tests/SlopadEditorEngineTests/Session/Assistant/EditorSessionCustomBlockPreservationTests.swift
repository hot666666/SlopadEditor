import Foundation
import Testing

import SlopadEditorCoreModel
@testable import SlopadEditorEngine

@Suite("custom block patch 보존 정책")
struct EditorSessionCustomBlockPreservationTests {
    private static let customKind = BlockKind.custom(
        typeID: "app.todo",
        version: 1,
        payload: Data("{\"id\":7}".utf8)
    )

    private static func makeSession() -> EditorSession {
        EditorSession(
            blocks: [
                EditorBlockInput(id: "intro", content: BlockContent(text: "intro")),
                EditorBlockInput(id: "custom", kind: customKind),
                EditorBlockInput(id: "outro", content: BlockContent(text: "outro")),
            ],
            selection: .text(
                TextSelection(
                    anchor: TextPosition(blockID: "intro", offset: 0),
                    focus: TextPosition(blockID: "intro", offset: 0)
                )
            ),
            textLayouter: DeterministicBlockTextLayouter()
        )
    }

    private static func patch(
        _ session: EditorSession,
        replacing blocks: [EditorBlockInput],
        policy: EditorCustomBlockPatchPolicy = .preserve
    ) throws -> EditorDocumentPatch {
        let context = try session.documentContextSnapshot()
        return EditorDocumentPatch(
            source: context.source,
            replacementBlocks: blocks,
            selectionAfter: context.selection,
            customBlockPolicy: policy
        )
    }

    @Test("custom block을 그대로 둔 patch는 적용된다")
    func appliesPatchThatKeepsCustomBlock() throws {
        // Given
        let session = Self.makeSession()

        // When
        let patch = try Self.patch(
            session,
            replacing: [
                EditorBlockInput(id: "intro", content: BlockContent(text: "edited")),
                EditorBlockInput(id: "custom", kind: Self.customKind),
                EditorBlockInput(id: "outro", content: BlockContent(text: "outro")),
            ]
        )

        // Then
        #expect(try session.applyDocumentPatch(patch) != nil)
    }

    @Test("custom block을 삭제한 patch는 capability 없이 거부된다")
    func rejectsPatchThatDropsCustomBlock() throws {
        // Given
        let session = Self.makeSession()

        // When
        let patch = try Self.patch(
            session,
            replacing: [
                EditorBlockInput(id: "intro", content: BlockContent(text: "intro")),
                EditorBlockInput(id: "outro", content: BlockContent(text: "outro")),
            ]
        )

        // Then
        #expect(throws: EditorDocumentTransactionError.customBlockNotPreserved("custom")) {
            try session.applyDocumentPatch(patch)
        }
    }

    @Test("payload나 version을 바꾼 patch도 거부된다")
    func rejectsPatchThatRewritesPayloadOrVersion() throws {
        // Given
        let rewrittenPayload = BlockKind.custom(
            typeID: "app.todo", version: 1, payload: Data("{\"id\":8}".utf8)
        )
        let rewrittenVersion = BlockKind.custom(
            typeID: "app.todo", version: 2, payload: Data("{\"id\":7}".utf8)
        )
        let retyped = BlockKind.custom(
            typeID: "app.other", version: 1, payload: Data("{\"id\":7}".utf8)
        )

        // When / Then
        for replacementKind in [rewrittenPayload, rewrittenVersion, retyped] {
            let session = Self.makeSession()
            let patch = try Self.patch(
                session,
                replacing: [
                    EditorBlockInput(id: "intro", content: BlockContent(text: "intro")),
                    EditorBlockInput(id: "custom", kind: replacementKind),
                    EditorBlockInput(id: "outro", content: BlockContent(text: "outro")),
                ]
            )
            #expect(throws: EditorDocumentTransactionError.customBlockNotPreserved("custom")) {
                try session.applyDocumentPatch(patch)
            }
        }
    }

    @Test("위치와 부모 변경은 보존 위반이 아니다")
    func allowsMovingCustomBlock() throws {
        // Given
        let session = Self.makeSession()

        // When — custom block이 intro의 자식으로 이동한다
        let patch = try Self.patch(
            session,
            replacing: [
                EditorBlockInput(id: "intro", content: BlockContent(text: "intro")),
                EditorBlockInput(id: "custom", parentID: "intro", kind: Self.customKind),
                EditorBlockInput(id: "outro", content: BlockContent(text: "outro")),
            ]
        )

        // Then
        #expect(try session.applyDocumentPatch(patch) != nil)
    }

    @Test("hostManaged capability는 custom block 제거를 허용한다")
    func hostManagedPolicyAllowsRemoval() throws {
        // Given
        let session = Self.makeSession()

        // When
        let patch = try Self.patch(
            session,
            replacing: [
                EditorBlockInput(id: "intro", content: BlockContent(text: "intro")),
                EditorBlockInput(id: "outro", content: BlockContent(text: "outro")),
            ],
            policy: .hostManaged
        )

        // Then
        #expect(try session.applyDocumentPatch(patch) != nil)
        #expect(!session.documentSnapshot.blocks.contains { $0.kind.isCustom })
    }

    @Test("hostManaged는 다른 canonical 불변식까지 통과시키지는 않는다")
    func hostManagedPolicyIsNotAValidationBypass() throws {
        // Given
        let session = Self.makeSession()

        // When — payload가 예산을 넘는다
        let patch = try Self.patch(
            session,
            replacing: [
                EditorBlockInput(id: "intro", content: BlockContent(text: "intro")),
                EditorBlockInput(
                    id: "custom",
                    kind: .custom(
                        typeID: "app.todo",
                        version: 1,
                        payload: Data(
                            repeating: 0x61,
                            count: BlockKind.customPayloadByteLimit + 1
                        )
                    )
                ),
                EditorBlockInput(id: "outro", content: BlockContent(text: "outro")),
            ],
            policy: .hostManaged
        )

        // Then
        #expect(throws: EditorDocumentTransactionError.customPayloadTooLarge("custom")) {
            try session.applyDocumentPatch(patch)
        }
    }
}
