import AppKit
import Darwin
import Foundation

struct SlopadDebugApp {
    fileprivate static let defaultWindowSize = NSSize(width: 720, height: 480)

    @MainActor
    private static var retainedDelegate: DebugAppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let options = DebugOptions(arguments: CommandLine.arguments)
        app.setActivationPolicy(.regular)
        if options.screenshotPath != nil {
            runScreenshotMode(options: options)
            return
        }

        let delegate = DebugAppDelegate(options: options)
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    @MainActor
    private static func runScreenshotMode(options: DebugOptions) {
        let viewController = DebugViewController(scenario: options.scenario)
        configureNativeInputTrace(for: viewController, options: options)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultWindowSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Slopad Debug"
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        layoutDebugWindow(window, viewController: viewController)
        viewController.performScenario(options.scenario)
        assertScenarioIfNeeded(viewController: viewController, options: options)
        window.displayIfNeeded()

        guard let screenshotPath = options.screenshotPath else { return }
        fputs(
            "SlopadDebugApp screenshot scenario=\(options.scenario) path=\(screenshotPath)\n", stderr
        )
        do {
            try viewController.writeScreenshot(to: screenshotPath)
            fputs("SlopadDebugApp wrote screenshot\n", stderr)
        } catch {
            fputs("SlopadDebugApp screenshot failed: \(error)\n", stderr)
        }
    }

    @MainActor
    fileprivate static func assertScenarioIfNeeded(
        viewController: DebugViewController,
        options: DebugOptions
    ) {
        guard options.assertState else { return }
        do {
            try viewController.assertScenarioState(options.scenario)
            fputs("SlopadDebugApp assertion passed scenario=\(options.scenario)\n", stderr)
        } catch {
            fputs(
                "SlopadDebugApp assertion failed scenario=\(options.scenario): \(error.localizedDescription)\n",
                stderr
            )
            exit(1)
        }
    }

    @MainActor
    fileprivate static func layoutDebugWindow(
        _ window: NSWindow,
        viewController: DebugViewController
    ) {
        let contentSize = window.contentLayoutRect.size
        let fallbackSize = window.frame.size
        let bounds = NSRect(
            x: 0,
            y: 0,
            width: max(contentSize.width, fallbackSize.width, defaultWindowSize.width),
            height: max(contentSize.height, fallbackSize.height, defaultWindowSize.height)
        )
        if let contentView = window.contentView {
            viewController.view.frame = bounds
            viewController.scrollView.frame = viewController.view.bounds
            viewController.scrollView.contentView.frame = viewController.scrollView.bounds
            viewController.scrollView.contentView.setBoundsOrigin(.zero)
            contentView.layoutSubtreeIfNeeded()
        }
        window.layoutIfNeeded()
        viewController.view.layoutSubtreeIfNeeded()
    }

    @MainActor
    fileprivate static func configureNativeInputTrace(
        for viewController: DebugViewController,
        options: DebugOptions
    ) {
        #if DEBUG
            guard options.nativeInputTrace else { return }
            let writer = DebugNativeInputTraceWriter()
            writer.writeProvenance()
            viewController.enableNativeInputTrace(writer.handler)
        #endif
    }
}

@MainActor
private final class DebugAppDelegate: NSObject, NSApplicationDelegate {
    private let options: DebugOptions
    private var window: NSWindow?
    private var viewController: DebugViewController?

    init(options: DebugOptions) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewController = DebugViewController(scenario: options.scenario)
        SlopadDebugApp.configureNativeInputTrace(for: viewController, options: options)
        let window = NSWindow(
            contentRect: NSRect(
                origin: NSPoint(x: 120, y: 120),
                size: SlopadDebugApp.defaultWindowSize
            ),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Slopad Debug"
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        self.viewController = viewController

        guard let screenshotPath = options.screenshotPath else { return }
        fputs(
            "SlopadDebugApp screenshot scenario=\(options.scenario) path=\(screenshotPath)\n", stderr
        )
        SlopadDebugApp.layoutDebugWindow(window, viewController: viewController)
        viewController.performScenario(options.scenario)
        SlopadDebugApp.assertScenarioIfNeeded(viewController: viewController, options: options)
        window.displayIfNeeded()
        do {
            try viewController.writeScreenshot(to: screenshotPath)
            fputs("SlopadDebugApp wrote screenshot\n", stderr)
        } catch {
            fputs("SlopadDebugApp screenshot failed: \(error)\n", stderr)
        }
        if options.autoExit {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private struct DebugOptions {
    var scenario: String = "wrap-input"
    var screenshotPath: String?
    var autoExit = false
    var assertState = false
    var nativeInputTrace = false

    init(arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--scenario":
                scenario = iterator.next() ?? scenario
            case "--screenshot":
                screenshotPath = iterator.next()
            case "--auto-exit":
                autoExit = true
            case "--assert-state":
                assertState = true
            case "--native-input-trace":
                nativeInputTrace = true
            default:
                continue
            }
        }
    }
}

SlopadDebugApp.main()
