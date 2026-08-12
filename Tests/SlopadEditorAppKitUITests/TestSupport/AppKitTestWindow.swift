import AppKit
import Testing

/// Swift tests retain their window with ARC, so `close()` must not also release it through
/// AppKit's legacy `isReleasedWhenClosed` ownership policy.
@MainActor
class AppKitTestWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        isReleasedWhenClosed = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

@MainActor
@Suite("AppKit test window lifetime")
struct AppKitTestWindowLifetimeTests {
    @Test("ARC가 소유한 test window는 explicit close 뒤 안전하게 해제된다")
    func arcOwnedWindowClosesWithoutAppKitRelease() {
        // Given
        _ = NSApplication.shared
        let window = AppKitTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // When
        window.orderOut(nil)
        window.close()

        // Then
        #expect(!window.isReleasedWhenClosed)
    }
}
