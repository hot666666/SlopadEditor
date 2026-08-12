// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SlopadEditor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SlopadEngine",
            targets: ["SlopadEngine"]
        ),
        .library(
            name: "SlopadEditorMarkdown",
            targets: ["SlopadEditorMarkdown"]
        ),
        .library(
            name: "SlopadEditorArchive",
            targets: ["SlopadEditorArchive"]
        ),
        .library(
            name: "SlopadEditorAppKit",
            targets: ["SlopadEditorAppKit"]
        ),
        .library(
            name: "SlopadEditorSwiftUI",
            targets: ["SlopadEditorSwiftUI"]
        ),
        .library(
            name: "SlopadEditorAppKitTextKit",
            targets: ["SlopadEditorAppKitTextKit"]
        ),
        .library(
            name: "SlopadEditorAppKitUI",
            targets: ["SlopadEditorAppKitUI"]
        ),
        .executable(
            name: "SlopadDebugApp",
            targets: ["SlopadDebugApp"]
        ),
        .executable(
            name: "SlopadUIBenchmarkApp",
            targets: ["SlopadUIBenchmarkApp"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-markdown.git",
            exact: "0.8.0"
        )
    ],
    targets: [
        .target(
            name: "SlopadCoreModel"
        ),
        // Markdown typed-input syntax is intentionally separate from the opt-in codec. It
        // contains only bounded pattern data and canonical rule effects — no parser target.
        .target(
            name: "SlopadEditorMarkdownInputRules",
            dependencies: ["SlopadCoreModel"]
        ),
        .target(
            name: "SlopadEditorMarkdown",
            dependencies: [
                "SlopadCoreModel",
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .target(
            name: "SlopadEditorArchive",
            dependencies: ["SlopadCoreModel"]
        ),
        .target(
            name: "SlopadEditorDataStructure"
        ),
        .target(
            name: "SlopadEditorModel",
            dependencies: ["SlopadCoreModel", "SlopadEditorMarkdownInputRules"]
        ),
        .target(
            name: "SlopadBlockLayout",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorDataStructure",
            ]
        ),
        .target(
            name: "SlopadEngine",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorModel",
                "SlopadBlockLayout",
            ]
        ),
        .target(
            name: "SlopadEditorAppKitTextKit",
            dependencies: ["SlopadCoreModel"]
        ),
        .target(
            name: "SlopadEditorAppKitUI",
            dependencies: [
                "SlopadEngine",
                "SlopadEditorAppKitTextKit",
            ]
        ),
        .target(
            name: "SlopadEditorAppKit",
            dependencies: [
                "SlopadEngine",
                "SlopadEditorAppKitUI",
            ]
        ),
        // Layered on top of the AppKit facade rather than folded into it, for the same
        // reason SlopadEditorAppKit is a curated umbrella and not a runtime owner.
        .target(
            name: "SlopadEditorSwiftUI",
            dependencies: ["SlopadEditorAppKit"]
        ),
        .executableTarget(
            name: "SlopadHeightBenchmark",
            dependencies: [
                "SlopadCoreModel",
                "SlopadBlockLayout",
            ],
            path: "Benchmarks/SlopadHeightBenchmark"
        ),
        .executableTarget(
            name: "SlopadSessionBenchmark",
            dependencies: ["SlopadEngine"],
            path: "Benchmarks/SlopadSessionBenchmark"
        ),
        .executableTarget(
            name: "SlopadDebugApp",
            dependencies: [
                "SlopadEngine",
                "SlopadEditorAppKitTextKit",
                "SlopadEditorAppKitUI",
            ],
            path: "Debug/SlopadDebugApp"
        ),
        .executableTarget(
            name: "SlopadUIBenchmarkApp",
            dependencies: [
                "SlopadEngine",
                "SlopadEditorAppKitTextKit",
                "SlopadEditorAppKitUI",
            ],
            path: "Benchmarks/SlopadUIBenchmarkApp"
        ),
        .testTarget(
            name: "SlopadEngineTests",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorDataStructure",
                "SlopadEditorModel",
                "SlopadBlockLayout",
                "SlopadEngine",
                "SlopadEditorMarkdown",
                "SlopadEditorMarkdownInputRules",
            ]
        ),
        .testTarget(
            name: "SlopadEditorMarkdownTests",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorMarkdown",
            ]
        ),
        .testTarget(
            name: "SlopadEditorArchiveTests",
            dependencies: [
                "SlopadEditorArchive",
                "SlopadCoreModel",
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SlopadEditorAppKitTextKitTests",
            dependencies: [
                "SlopadCoreModel",
                "SlopadEditorAppKitTextKit",
            ]
        ),
        .testTarget(
            name: "SlopadEditorAppKitUITests",
            dependencies: [
                "SlopadEngine",
                "SlopadEditorAppKitUI",
            ]
        ),
        // SlopadEditorAppKit is a test-only dependency: the tests construct a controller directly
        // to stand in for what `makeNSViewController` produces. SlopadEditorSwiftUI deliberately
        // does not re-export the controller, so a SwiftUI host cannot reach around it.
        .testTarget(
            name: "SlopadEditorSwiftUITests",
            dependencies: [
                "SlopadEditorSwiftUI",
                "SlopadEditorAppKit",
            ]
        ),
    ]
)
