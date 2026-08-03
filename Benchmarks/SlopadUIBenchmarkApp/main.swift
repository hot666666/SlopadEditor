import AppKit
import Darwin
import Foundation

struct SlopadUIBenchmarkApp {
    @MainActor
    private static var retainedDelegate: UIBenchmarkAppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let options = UIBenchmarkCommandLineOptions(arguments: CommandLine.arguments)
        app.setActivationPolicy(.regular)

        let delegate = UIBenchmarkAppDelegate(options: options)
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    @MainActor
    fileprivate static func layoutBenchmarkWindow(
        _ window: NSWindow,
        host: UIBenchmarkHost
    ) {
        let contentSize = window.contentLayoutRect.size
        let fallbackSize = window.frame.size
        let bounds = NSRect(
            x: 0,
            y: 0,
            width: max(contentSize.width, fallbackSize.width, 920),
            height: max(contentSize.height, fallbackSize.height, 680)
        )
        if let contentView = window.contentView {
            host.editorViewController.view.frame = bounds
            host.scrollView.frame = host.editorViewController.view.bounds
            host.scrollView.contentView.frame = host.scrollView.bounds
            host.scrollView.contentView.setBoundsOrigin(.zero)
            contentView.layoutSubtreeIfNeeded()
        }
        window.layoutIfNeeded()
        host.editorViewController.view.layoutSubtreeIfNeeded()
    }
}

@MainActor
private final class UIBenchmarkAppDelegate: NSObject, NSApplicationDelegate {
    private let options: UIBenchmarkCommandLineOptions
    private var window: NSWindow?
    private var host: UIBenchmarkHost?

    init(options: UIBenchmarkCommandLineOptions) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = UIBenchmarkHost(
            blockCount: options.blockCount,
            scenario: options.scenario,
            subtreeNodeCount: options.subtreeNodeCount,
            activeTextLength: options.activeTextLength
        )
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 920, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Slopad UI Benchmark"
        window.contentViewController = host.editorViewController
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        self.host = host

        SlopadUIBenchmarkApp.layoutBenchmarkWindow(window, host: host)
        do {
            try UIBenchmarkRunner.run(
                window: window,
                viewController: host,
                options: UIBenchmarkOptions(
                    scenario: options.scenario,
                    blockCount: options.blockCount,
                    activeTextLength: options.activeTextLength,
                    frameCount: options.frameCount,
                    outputPath: options.outputPath,
                    subtreeNodeCount: options.subtreeNodeCount
                )
            )
        } catch {
            fputs("SlopadUIBenchmarkApp failed: \(error)\n", stderr)
            exit(1)
        }
        NSApp.terminate(nil)
    }
}

private struct UIBenchmarkCommandLineOptions {
    var scenario = "scroll"
    var blockCount = 10_000
    var activeTextLength: Int?
    var frameCount = 120
    var outputPath = "/tmp/slopad-ui-benchmark.csv"
    var subtreeNodeCount: Int?

    init(arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--scenario", "--ui-benchmark-scenario":
                scenario = iterator.next() ?? scenario
            case "--output", "--ui-benchmark-output":
                outputPath = iterator.next() ?? outputPath
            case "--block-count", "--ui-benchmark-block-count":
                if let value = iterator.next(), let count = Int(value) {
                    blockCount = max(2, count)
                }
            case "--active-text-length", "--ui-benchmark-active-text-length":
                if let value = iterator.next(), let count = Int(value) {
                    activeTextLength = max(1, count)
                }
            case "--frames", "--ui-benchmark-frames":
                if let value = iterator.next(), let count = Int(value) {
                    frameCount = max(1, count)
                }
            case "--subtree-node-count", "--ui-benchmark-subtree-node-count":
                if let value = iterator.next(), let count = Int(value) {
                    subtreeNodeCount = max(1, count)
                }
            default:
                continue
            }
        }
    }
}

SlopadUIBenchmarkApp.main()
