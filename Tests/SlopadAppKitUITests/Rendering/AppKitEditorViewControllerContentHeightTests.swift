import AppKit
import Testing

import SlopadEngine
@testable import SlopadAppKitUI

@MainActor
@Suite("AppKit content height 관찰")
struct AppKitEditorViewControllerContentHeightTests {
    @Test("최초 레이아웃이 초기 높이를 한 번 발화한다")
    func initialLayoutPublishesAHeight() {
        // Given: 호스트는 초기값을 얻을 경로가 있어야 한다.
        let controller = makeController(blockCount: 3)
        var observed: [Double] = []
        controller.onContentHeightChange = { observed.append($0) }

        // When
        attach(controller)

        // Then
        #expect(observed.count == 1)
        #expect(observed.first == controller.contentHeight)
        #expect(controller.contentHeight > 0)
    }

    @Test("문서가 길어지면 새 높이로 발화한다")
    func heightGrowsWithTheDocument() {
        // Given
        let controller = makeController(blockCount: 1)
        attach(controller)
        let initialHeight = controller.contentHeight

        var observed: [Double] = []
        controller.onContentHeightChange = { observed.append($0) }

        // When
        controller.perform(.enter, makeFirstResponder: false, scrollSelectionIntoView: false)

        // Then
        #expect(observed.count == 1)
        #expect(controller.contentHeight > initialHeight)
    }

    @Test("scroll만 했을 때는 발화하지 않는다")
    func scrollingDoesNotPublishHeight() {
        // Given: onSnapshotChanged와의 차이가 정확히 이것이다.
        let controller = makeController(blockCount: 60)
        attach(controller)

        var heightEvents = 0
        var snapshotEvents = 0
        controller.onContentHeightChange = { _ in heightEvents += 1 }
        controller.onSnapshotChanged = { _ in snapshotEvents += 1 }

        // When
        controller.scrollDocument(to: 120)
        controller.scrollDocument(to: 240)

        // Then
        #expect(heightEvents == 0)
        #expect(snapshotEvents > 0)
    }

    @Test("selection만 바뀌면 발화하지 않는다")
    func selectionChangeDoesNotPublishHeight() {
        // Given
        let controller = makeController(blockCount: 4)
        attach(controller)

        var heightEvents = 0
        controller.onContentHeightChange = { _ in heightEvents += 1 }

        // When
        controller.perform(.moveRight, makeFirstResponder: false, scrollSelectionIntoView: false)
        controller.perform(
            .extendCharacterRight,
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )

        // Then
        #expect(heightEvents == 0)
    }

    @Test("같은 높이가 다시 계산돼도 다시 발화하지 않는다")
    func recomputingTheSameHeightIsSilent() {
        // Given
        let controller = makeController(blockCount: 3)
        attach(controller)

        var heightEvents = 0
        controller.onContentHeightChange = { _ in heightEvents += 1 }

        // When: 문서 높이를 바꾸지 않는 편집을 반복한다.
        for text in ["a", "b", "c"] {
            controller.perform(
                .insertText(text),
                makeFirstResponder: false,
                scrollSelectionIntoView: false
            )
        }

        // Then
        #expect(heightEvents == 0)
    }

    @Test("스타일 변경으로 높이가 달라지면 발화한다")
    func styleChangePublishesHeight() {
        // Given
        let controller = makeController(blockCount: 3)
        attach(controller)
        let initialHeight = controller.contentHeight

        var observed: [Double] = []
        controller.onContentHeightChange = { observed.append($0) }

        // When
        controller.updateEditorStyle(AppKitEditorStyle(fontSize: 34, lineHeightMultiple: 2.0))

        // Then
        #expect(!observed.isEmpty)
        #expect(controller.contentHeight != initialHeight)
        #expect(observed.last == controller.contentHeight)
    }

    @Test("발화되는 값이 snapshot의 totalHeight와 같다")
    func publishedHeightMatchesTheSnapshot() throws {
        // Given
        let controller = makeController(blockCount: 5)
        var observed: Double?
        controller.onContentHeightChange = { observed = $0 }

        // When
        attach(controller)

        // Then: bottom padding은 포함하지 않는다.
        let snapshot = try #require(controller.snapshot)
        #expect(observed == snapshot.totalHeight)
        #expect(controller.contentHeight == snapshot.totalHeight)
    }
}

// MARK: - Support

@MainActor
private func makeController(blockCount: Int) -> AppKitEditorViewController {
    let blocks = (0..<blockCount).map { index in
        EditorBlockInput(
            id: BlockID("block-\(index)"),
            content: BlockContent(text: "Block \(index)")
        )
    }
    return AppKitEditorViewController(
        blocks: blocks,
        selection: .caret(blockID: "block-0", offset: 0)
    )
}

@MainActor
private func attach(_ controller: AppKitEditorViewController) {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentViewController = controller
    controller.view.layoutSubtreeIfNeeded()
}
