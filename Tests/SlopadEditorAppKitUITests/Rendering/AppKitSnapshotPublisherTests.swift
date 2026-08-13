import SlopadEditorCoreModel
import SlopadEditorEngine
import Testing

@testable import SlopadEditorAppKitUI

// These exercise the publication rule directly. Before it owned its own type the rule could
// only be reached through a mounted `NSWindow`, so the reentrancy behaviour below was never
// asserted on its own.
@MainActor
@Suite("AppKit 스냅샷 발행 중복 제거")
struct AppKitSnapshotPublisherTests {
    private func makeSession() -> EditorSession {
        EditorSession(
            blocks: [
                EditorBlockInput(kind: .paragraph, content: BlockContent(text: "첫 문단")),
                EditorBlockInput(kind: .paragraph, content: BlockContent(text: "둘째 문단")),
            ],
            textLayouter: AppKitTextSystem(style: AppKitEditorStyle()).textLayouter
        )
    }

    private let viewport = EditorViewport(width: 600, scrollY: 0, height: 400)

    @Test("같은 표면을 다시 발행하지 않는다")
    func doesNotRepublishAnIdenticalSurface() {
        // Given
        let session = makeSession()
        let snapshot = session.render(in: viewport)
        let publisher = AppKitSnapshotPublisher()
        var delivered = 0

        // When
        publisher.publish(snapshot, viewport: viewport) { _ in delivered += 1 }
        publisher.publish(snapshot, viewport: viewport) { _ in delivered += 1 }

        // Then
        #expect(delivered == 2)
    }

    @Test("뷰포트만 달라져도 별개의 표면으로 발행한다")
    func republishesWhenOnlyTheViewportChanges() {
        // Given
        let session = makeSession()
        let snapshot = session.render(in: viewport)
        let scrolled = EditorViewport(width: 600, scrollY: 120, height: 400)
        let publisher = AppKitSnapshotPublisher()
        var delivered = 0

        // When
        publisher.publish(snapshot, viewport: viewport) { _ in delivered += 1 }
        publisher.publish(snapshot, viewport: scrolled) { _ in delivered += 1 }

        // Then
        #expect(delivered == 2)
    }

    @Test("전달 중 재진입한 같은 표면은 다시 발행되지 않는다")
    func suppressesReentrantPublicationOfTheSameSurface() {
        // Given
        let session = makeSession()
        let snapshot = session.render(in: viewport)
        let publisher = AppKitSnapshotPublisher()
        var delivered = 0

        // When: 호스트가 콜백 안에서 같은 표면을 다시 발행하려 한다
        publisher.publish(snapshot, viewport: viewport) { _ in
            delivered += 1
            publisher.publish(snapshot, viewport: viewport) { _ in delivered += 1 }
        }

        // Then
        #expect(delivered == 1)
    }

    @Test("전달 중에는 그 표면이 활성 발행으로 보인다")
    func reportsTheInFlightSurfaceAsActive() {
        // Given
        let session = makeSession()
        let snapshot = session.render(in: viewport)
        let publisher = AppKitSnapshotPublisher()
        var activeDuringDelivery = false

        // When
        publisher.publish(snapshot, viewport: viewport) { _ in
            activeDuringDelivery = publisher.isActivePublication(
                viewport: viewport,
                snapshot: snapshot
            )
        }

        // Then
        #expect(activeDuringDelivery)
        #expect(!publisher.isActivePublication(viewport: viewport, snapshot: snapshot))
    }
}
