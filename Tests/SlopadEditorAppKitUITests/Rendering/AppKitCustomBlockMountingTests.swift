import AppKit
import Foundation
import Testing

@testable import SlopadEditorAppKitUI

@MainActor
@Suite("AppKit custom block 마운트 조정")
struct AppKitCustomBlockMountingTests {
    private final class RecordingProvider: AppKitCustomBlockProvider {
        let handledTypeIDs: Set<String>
        private(set) var madeTypeIDs: [String] = []
        private(set) var updates: [(typeID: String, version: Int, payload: Data)] = []
        private(set) var recycledCount = 0

        init(handling handledTypeIDs: Set<String>) {
            self.handledTypeIDs = handledTypeIDs
        }

        func handles(typeID: String) -> Bool { handledTypeIDs.contains(typeID) }

        func makeBody(typeID: String) -> NSView {
            madeTypeIDs.append(typeID)
            return NSView(frame: .zero)
        }

        func update(_ body: NSView, typeID: String, version: Int, payload: Data) {
            updates.append((typeID, version, payload))
        }

        func recycle(_ body: NSView) { recycledCount += 1 }
    }

    private func body(
        _ blockID: String,
        typeID: String = "app.todo",
        version: Int = 1,
        payload: String = "a",
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 40)
    ) -> AppKitCustomBlockMountController.VisibleBody {
        AppKitCustomBlockMountController.VisibleBody(
            blockID: .init(blockID),
            typeID: typeID,
            version: version,
            payload: Data(payload.utf8),
            frame: frame
        )
    }

    @Test("보이는 custom block마다 host view를 한 번 만들어 컨테이너에 붙인다")
    func mountsVisibleBodies() {
        // Given
        let container = NSView()
        let provider = RecordingProvider(handling: ["app.todo"])
        let controller = AppKitCustomBlockMountController()
        controller.provider = provider

        // When
        controller.reconcile([body("a"), body("b")], in: container)

        // Then
        #expect(provider.madeTypeIDs == ["app.todo", "app.todo"])
        #expect(container.subviews.count == 2)
        #expect(controller.mounted.count == 2)
    }

    @Test("같은 payload로 다시 조정하면 새로 만들지도 갱신하지도 않는다")
    func reusesMountedBodyWhenNothingChanged() {
        // Given
        let container = NSView()
        let provider = RecordingProvider(handling: ["app.todo"])
        let controller = AppKitCustomBlockMountController()
        controller.provider = provider
        controller.reconcile([body("a")], in: container)

        // When
        controller.reconcile([body("a")], in: container)

        // Then
        #expect(provider.madeTypeIDs.count == 1)
        #expect(provider.updates.count == 1)
        #expect(container.subviews.count == 1)
    }

    @Test("payload가 바뀌면 뷰를 다시 만들지 않고 제자리에서 갱신한다")
    func updatesInPlaceWhenPayloadChanges() {
        // Given
        let container = NSView()
        let provider = RecordingProvider(handling: ["app.todo"])
        let controller = AppKitCustomBlockMountController()
        controller.provider = provider
        controller.reconcile([body("a", payload: "one")], in: container)

        // When
        controller.reconcile([body("a", payload: "two")], in: container)

        // Then
        #expect(provider.madeTypeIDs.count == 1)
        #expect(provider.updates.count == 2)
        #expect(provider.updates.last?.payload == Data("two".utf8))
    }

    @Test("frame만 바뀌면 갱신 없이 위치만 옮긴다 — 스크롤이 이 경로다")
    func movesWithoutUpdatingWhenOnlyFrameChanges() {
        // Given
        let container = NSView()
        let provider = RecordingProvider(handling: ["app.todo"])
        let controller = AppKitCustomBlockMountController()
        controller.provider = provider
        controller.reconcile([body("a", frame: CGRect(x: 0, y: 0, width: 100, height: 40))], in: container)

        // When
        let moved = CGRect(x: 0, y: 250, width: 100, height: 40)
        controller.reconcile([body("a", frame: moved)], in: container)

        // Then
        #expect(provider.updates.count == 1)
        #expect(controller.mounted[.init("a")]?.frame == moved)
        #expect(container.subviews.first?.frame == moved)
    }

    @Test("화면에서 벗어난 블록은 떼어내고 provider에 반납한다")
    func releasesBodiesThatLeftTheVisibleRegion() {
        // Given
        let container = NSView()
        let provider = RecordingProvider(handling: ["app.todo"])
        let controller = AppKitCustomBlockMountController()
        controller.provider = provider
        controller.reconcile([body("a"), body("b")], in: container)

        // When
        controller.reconcile([body("b")], in: container)

        // Then
        #expect(controller.mounted.keys.map(\.rawValue) == ["b"])
        #expect(container.subviews.count == 1)
        #expect(provider.recycledCount == 1)
    }

    @Test("같은 id가 다른 typeID로 바뀌면 이전 뷰를 반납하고 새로 만든다")
    func replacesBodyWhenTypeChanges() {
        // Given
        let container = NSView()
        let provider = RecordingProvider(handling: ["app.todo", "app.chart"])
        let controller = AppKitCustomBlockMountController()
        controller.provider = provider
        controller.reconcile([body("a", typeID: "app.todo")], in: container)

        // When
        controller.reconcile([body("a", typeID: "app.chart")], in: container)

        // Then
        #expect(provider.madeTypeIDs == ["app.todo", "app.chart"])
        #expect(provider.recycledCount == 1)
        #expect(container.subviews.count == 1)
    }

    @Test("provider가 다루지 않는 타입은 마운트하지 않는다 — placeholder 영역으로 남는다")
    func ignoresUnhandledTypeIDs() {
        // Given
        let container = NSView()
        let provider = RecordingProvider(handling: ["app.todo"])
        let controller = AppKitCustomBlockMountController()
        controller.provider = provider

        // When
        controller.reconcile([body("a", typeID: "app.unknown")], in: container)

        // Then
        #expect(provider.madeTypeIDs.isEmpty)
        #expect(container.subviews.isEmpty)
        #expect(controller.mounted.isEmpty)
    }

    @Test("provider가 없으면 이미 붙은 뷰까지 모두 떼어낸다")
    func releasesEverythingWhenProviderGoesAway() {
        // Given
        let container = NSView()
        let provider = RecordingProvider(handling: ["app.todo"])
        let controller = AppKitCustomBlockMountController()
        controller.provider = provider
        controller.reconcile([body("a")], in: container)

        // When
        controller.provider = nil
        controller.reconcile([body("a")], in: container)

        // Then
        #expect(controller.mounted.isEmpty)
        #expect(container.subviews.isEmpty)
    }
}
